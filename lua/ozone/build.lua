local Script = require("ozone.script")
local fs = require("ozone.x.fs")

---@class ozone.Build.PluginSpec
---@field path? string Plugin directory path
---@field url? string Git repository URL
---@field version? string Git ref (branch, tag, or revision)

---@class ozone.Build.PluginSourcePath
---@field kind "path"

---@class ozone.Build.PluginSourceGit
---@field kind "git"
---@field url string
---@field version? string

---@alias ozone.Build.PluginSource ozone.Build.PluginSourcePath | ozone.Build.PluginSourceGit

---@class ozone.Build.ResolvedPluginSpec
---@field path string
---@field source ozone.Build.PluginSource

---@class ozone.Build
---@field private _plugins table<string, ozone.Build.ResolvedPluginSpec>
---@field private _errors string[]
---@field private _install_root string
---@field private _output_path string
local Build = {}
---@private
Build.__index = Build

---@param name string
---@return string
local function sanitize_plugin_name(name)
    local sanitized_name = name:gsub("[^%w_.-]", "-")
    if sanitized_name == "" then
        return "plugin"
    end
    return sanitized_name
end

---@return self
function Build.new()
    return setmetatable({
        _plugins = {},
        _errors = {},
        _install_root = vim.fn.stdpath("data") .. "/ozone/_",
        _output_path = vim.fn.stdpath("data") .. "/ozone/main",
    }, Build)
end

---@param message any
---@return nil
function Build:add_error(message)
    table.insert(self._errors, type(message) == "string" and message or tostring(message))
end

---@return string[] errors
function Build:get_errors()
    local errors = {} ---@type string[]
    for i, message in ipairs(self._errors) do
        errors[i] = message
    end
    return errors
end

---@param name string
---@return string
function Build:_default_plugin_path(name)
    return vim.fs.joinpath(self._install_root, sanitize_plugin_name(name))
end

---@param name string
---@param spec ozone.Build.PluginSpec
---@return ozone.Build.ResolvedPluginSpec? resolved_spec
---@return string? err
function Build:_normalize_plugin_spec(name, spec)
    if type(spec) ~= "table" then
        return nil, ("plugin %q spec must be a table"):format(name)
    end

    local path = spec.path
    if path ~= nil then
        if type(path) ~= "string" then
            return nil, ("plugin %q: `path` must be a string"):format(name)
        end
        if path == "" then
            return nil, ("plugin %q: `path` must not be empty"):format(name)
        end
        path = vim.fs.normalize(path)
    end

    local url = spec.url
    if url ~= nil then
        if type(url) ~= "string" then
            return nil, ("plugin %q: `url` must be a string"):format(name)
        end
        if url == "" then
            return nil, ("plugin %q: `url` must not be empty"):format(name)
        end
    end

    local version = spec.version
    if version ~= nil then
        if type(version) ~= "string" then
            return nil, ("plugin %q: `version` must be a string"):format(name)
        end
        if version == "" then
            return nil, ("plugin %q: `version` must not be empty"):format(name)
        end
    end

    if version and not url then
        return nil, ("plugin %q: `version` requires `url`"):format(name)
    end

    if url then
        return {
            path = path or self:_default_plugin_path(name),
            source = {
                kind = "git",
                url = url,
                version = version,
            },
        }
    end

    if path then
        return {
            path = path,
            source = {
                kind = "path",
            },
        },
            nil
    end

    return nil, ("plugin %q must define `path` or `url`"):format(name)
end

---@param name string
---@param path string
---@param version string
---@return boolean? success
---@return string? err
function Build:_checkout_git_plugin_version(name, path, version)
    local result = vim.system({
        "git",
        "-C",
        path,
        "checkout",
        version,
    }, { text = true }):wait()
    if result.code ~= 0 or result.signal ~= 0 then
        local stdout = type(result.stdout) == "string" and result.stdout or ""
        local stderr = type(result.stderr) == "string" and result.stderr or ""
        return nil,
            ("plugin %q checkout failed: %s at %s (code=%d, signal=%d)%s%s"):format(
                name,
                version,
                path,
                result.code,
                result.signal,
                stdout ~= "" and ("\n---- stdout ----\n" .. stdout) or "",
                stderr ~= "" and ("\n---- stderr ----\n" .. stderr) or ""
            )
    end

    return true, nil
end

---@param name string
---@param spec ozone.Build.ResolvedPluginSpec
---@return boolean? success
---@return string? err
function Build:_install_git_plugin(name, spec)
    local source = spec.source
    if source.kind ~= "git" then
        return nil,
            ("plugin %q has unsupported source kind: %s"):format(name, tostring(source.kind))
    end
    if fs.exists(spec.path) then
        if fs.is_dir(spec.path) then
            if source.version then
                return self:_checkout_git_plugin_version(name, spec.path, source.version)
            end
            return true, nil
        end
        return nil,
            ("plugin %q install path exists and is not a directory: %s"):format(name, spec.path)
    end

    local parent_dir = vim.fs.dirname(spec.path)
    if parent_dir then
        local success, create_dir_err = fs.create_dir_all(parent_dir)
        if not success then
            return nil,
                ("plugin %q failed to create parent directory %s: %s"):format(
                    name,
                    parent_dir,
                    create_dir_err or "unknown error"
                )
        end
    end

    local result = vim.system({
        "git",
        "clone",
        "--filter=blob:none",
        source.url,
        spec.path,
    }, { text = true }):wait()
    if result.code ~= 0 or result.signal ~= 0 then
        local stdout = type(result.stdout) == "string" and result.stdout or ""
        local stderr = type(result.stderr) == "string" and result.stderr or ""
        return nil,
            ("plugin %q clone failed: %s -> %s (code=%d, signal=%d)%s%s"):format(
                name,
                source.url,
                spec.path,
                result.code,
                result.signal,
                stdout ~= "" and ("\n---- stdout ----\n" .. stdout) or "",
                stderr ~= "" and ("\n---- stderr ----\n" .. stderr) or ""
            )
    end

    if source.version then
        return self:_checkout_git_plugin_version(name, spec.path, source.version)
    end

    return true, nil
end

---@param name string
---@param spec ozone.Build.ResolvedPluginSpec
---@return boolean? success
---@return string? err
function Build:_install_plugin(name, spec)
    if spec.source.kind == "git" then
        return self:_install_git_plugin(name, spec)
    end

    if spec.source.kind ~= "path" then
        return nil,
            ("plugin %q has unsupported source kind: %s"):format(name, tostring(spec.source.kind))
    end

    return true, nil
end

---@param name string
---@param spec ozone.Build.PluginSpec
---@return nil
function Build:add_plugin(name, spec)
    local resolved_spec, err = self:_normalize_plugin_spec(name, spec)
    if not resolved_spec then
        self:add_error(err)
        return
    end
    self._plugins[name] = resolved_spec
end

---@return string? path
function Build:generate_script()
    local script = Script.new()
    for name, spec in pairs(self._plugins) do
        local success, install_err = self:_install_plugin(name, spec)
        if not success then
            self:add_error(install_err)
        end
        if fs.is_dir(spec.path) then
            table.insert(script.rtp_prefix, spec.path)
            if fs.is_dir(spec.path .. "/after") then
                table.insert(script.rtp_suffix, spec.path .. "/after")
            end
        elseif spec.source.kind == "path" then
            self:add_error(("plugin %q path is not a directory: %s"):format(name, spec.path))
        end
    end

    local output_dir = vim.fs.dirname(self._output_path)
    if not output_dir then
        self:add_error(("failed to determine output directory: %s"):format(self._output_path))
        return nil
    end

    local success, create_dir_err = fs.create_dir_all(output_dir)
    if not success then
        self:add_error(
            ("failed to create output directory %s: %s"):format(
                output_dir,
                create_dir_err or "unknown error"
            )
        )
        return nil
    end

    local wrote, write_err = fs.write_file(self._output_path, script:tostring())
    if not wrote then
        self:add_error(
            ("failed to write generated script %s: %s"):format(
                self._output_path,
                write_err or "unknown error"
            )
        )
        return nil
    end

    return self._output_path
end

return Build
