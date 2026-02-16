local Queue = require("ozone.x.queue")
local coro = require("ozone.x.coro")
local fs = require("ozone.x.fs")

local Script = require("ozone.script")
local git = require("ozone.git")

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
---@field private _plugin_name_counts table<string, integer>
---@field private _install_root string
---@field private _output_path string
local Build = {}
---@private
Build.__index = Build

---@class ozone.Build.PluginBuildResult
---@field name string
---@field spec ozone.Build.ResolvedPluginSpec
---@field path_is_dir boolean
---@field has_after_dir boolean

---@param name any
---@return boolean
local function is_valid_plugin_name(name)
    return type(name) == "string" and name:match("^[%w_.-]+$") ~= nil
end

---@return self
function Build.new()
    return setmetatable({
        _plugins = {},
        _errors = {},
        _plugin_name_counts = {},
        _install_root = vim.fn.stdpath("data") .. "/ozone/_",
        _output_path = vim.fn.stdpath("data") .. "/ozone/main",
    }, Build)
end

---@param fmt any
---@param ... any
---@return nil
function Build:err(fmt, ...)
    table.insert(self._errors, tostring(fmt):format(...))
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
    return vim.fs.joinpath(self._install_root, name)
end

---@param name string
---@param spec ozone.Build.PluginSpec
---@return ozone.Build.ResolvedPluginSpec? resolved_spec
function Build:_validate_plugin_spec(name, spec)
    vim.validate(
        "name",
        name,
        is_valid_plugin_name,
        false,
        "plugin name (letters, digits, '_', '.', '-')"
    )
    vim.validate("spec", spec, "table")

    local path = spec.path
    local url = spec.url
    local version = spec.version

    vim.validate("path", path, function(value)
        return type(value) == "string" and value ~= ""
    end, true, "non-empty string")
    vim.validate("url", url, function(value)
        return type(value) == "string" and value ~= ""
    end, true, "non-empty string")
    vim.validate("version", version, function(value)
        return type(value) == "string" and value ~= ""
    end, true, "non-empty string")
    vim.validate("version_source", { version = version, url = url }, function(value)
        return value.version == nil or value.url ~= nil
    end, false, "`version` requires `url`")
    vim.validate("source", { path = path, url = url }, function(value)
        return value.path ~= nil or value.url ~= nil
    end, false, "`path` or `url` must be set")

    local name_count = (self._plugin_name_counts[name] or 0) + 1
    self._plugin_name_counts[name] = name_count

    if name_count > 1 then
        if name_count == 2 then
            self:err("plugin %q: duplicate name (definition #1)", name)
        end
        self:err("plugin %q: duplicate name (definition #%d)", name, name_count)
        self._plugins[name] = nil
        return nil
    end

    if path ~= nil then
        path = vim.fs.normalize(path)
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

    return {
        path = path,
        source = {
            kind = "path",
        },
    }
end

---@param name string
---@param path string
---@param version string
function Build:_checkout_git_plugin_version(name, path, version)
    local success, checkout_err = git.checkout(path, version)
    if not success then
        error(("plugin %q %s"):format(name, checkout_err or "checkout failed"))
    end
end

---@param name string
---@param spec ozone.Build.ResolvedPluginSpec
function Build:_install_git_plugin(name, spec)
    local source = spec.source
    if source.kind ~= "git" then
        error(("plugin %q has unsupported source kind: %s"):format(name, source.kind))
    end
    if fs.exists(spec.path) then
        if fs.is_dir(spec.path) then
            if source.version then
                self:_checkout_git_plugin_version(name, spec.path, source.version)
            end
            return
        end
        error(("plugin %q install path exists and is not a directory: %s"):format(name, spec.path))
    end

    local parent_dir = vim.fs.dirname(spec.path)
    if parent_dir then
        local success, create_dir_err = fs.create_dir_all(parent_dir)
        if not success and not fs.is_dir(parent_dir) then
            error(
                ("plugin %q failed to create parent directory %s: %s"):format(
                    name,
                    parent_dir,
                    create_dir_err or "unknown error"
                )
            )
        end
    end

    local success, clone_err = git.clone(source.url, spec.path)
    if not success then
        error(("plugin %q %s"):format(name, clone_err or "clone failed"))
    end

    if source.version then
        self:_checkout_git_plugin_version(name, spec.path, source.version)
    end
end

---@param name string
---@param spec ozone.Build.ResolvedPluginSpec
function Build:_install_plugin(name, spec)
    if spec.source.kind == "git" then
        self:_install_git_plugin(name, spec)
        return
    end

    if spec.source.kind ~= "path" then
        error(("plugin %q has unsupported source kind: %s"):format(name, spec.source.kind))
    end
end

---@param name string
---@param spec ozone.Build.PluginSpec
---@return nil
function Build:add_plugin(name, spec)
    local resolved_spec = self:_validate_plugin_spec(name, spec)
    if not resolved_spec then
        return
    end

    self._plugins[name] = resolved_spec
end

---@return string? path
function Build:generate_script()
    local script = Script.new()
    local queue = Queue.new()
    local pending = 0 ---@type integer
    local names = {} ---@type string[]

    for name, spec in pairs(self._plugins) do
        table.insert(names, name)
        pending = pending + 1
        coro.pspawn(queue.put_fn, function(plugin_name, plugin_spec)
            self:_install_plugin(plugin_name, plugin_spec)
            local path_is_dir = fs.is_dir(plugin_spec.path)
            local has_after_dir = path_is_dir and fs.is_dir(plugin_spec.path .. "/after") or false
            return {
                name = plugin_name,
                spec = plugin_spec,
                path_is_dir = path_is_dir,
                has_after_dir = has_after_dir,
            }
        end, name, spec)
    end

    local results = {} ---@type table<string, ozone.Build.PluginBuildResult>

    for _ = 1, pending do
        local co_success, result_or_err = queue:get()
        if not co_success then
            self:err("%s", result_or_err or "unknown error")
        else
            local result = result_or_err ---@type ozone.Build.PluginBuildResult
            results[result.name] = result
        end
    end

    for _, name in ipairs(names) do
        local result = results[name]
        if result then
            if result.path_is_dir then
                table.insert(script.rtp_prefix, result.spec.path)
                if result.has_after_dir then
                    table.insert(script.rtp_suffix, result.spec.path .. "/after")
                end
            elseif result.spec.source.kind == "path" then
                self:err("plugin %q path is not a directory: %s", name, result.spec.path)
            end
        end
    end

    local output_dir = vim.fs.dirname(self._output_path)
    if not output_dir then
        self:err("failed to determine output directory: %s", self._output_path)
        return nil
    end

    local success, create_dir_err = fs.create_dir_all(output_dir)
    if not success then
        self:err(
            "failed to create output directory %s: %s",
            output_dir,
            create_dir_err or "unknown error"
        )
        return nil
    end

    local wrote, write_err = fs.write_file(self._output_path, script:tostring())
    if not wrote then
        self:err(
            "failed to write generated script %s: %s",
            self._output_path,
            write_err or "unknown error"
        )
        return nil
    end

    return self._output_path
end

return Build
