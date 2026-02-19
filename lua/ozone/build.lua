local Queue = require("ozone.x.queue")
local coro = require("ozone.x.coro")
local fs = require("ozone.x.fs")

local Script = require("ozone.script")
local git = require("ozone.git")

---@class ozone.Build.PluginSpec
---@field path? string Plugin directory path
---@field url? string Git repository URL
---@field version? string Git ref (branch, tag, or revision)

---@class ozone.Build
---@field private _errors string[]
---@field private _output_path string
local Build = {}
---@private
Build.__index = Build

---@class ozone.Build.PluginBuildResult
---@field name string
---@field spec ozone.Config.PluginSpec
---@field path_is_dir boolean
---@field has_after_dir boolean

---@return self
function Build.new()
    return setmetatable({
        _errors = {},
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
---@param path string
---@param version string
function Build:_checkout_git_plugin_version(name, path, version)
    local success, checkout_err = git.checkout(path, version)
    if not success then
        error(("plugin %q %s"):format(name, checkout_err or "checkout failed"))
    end
end

---@param spec ozone.Config.PluginSpec
local function install_git_plugin(spec)
    local source = spec.source
    if source.kind ~= "git" then
        return
    end
    if fs.exists(spec.path) then
        if fs.is_dir(spec.path) then
            if source.version then
                local checkout_success, checkout_err = git.checkout(spec.path, source.version)
                if not checkout_success then
                    error(checkout_err or "checkout failed", 0)
                end
            end
            return
        end
        error(("install path exists and is not a directory: %s"):format(spec.path))
    end

    -- `git clone` can create missing parent directories recursively for destination paths
    local clone_success, clone_err = git.clone(source.url, spec.path)
    if not clone_success then
        error(clone_err or "clone failed", 0)
    end

    if source.version then
        local checkout_success, checkout_err = git.checkout(spec.path, source.version)
        if not checkout_success then
            error(checkout_err or "checkout failed", 0)
        end
    end
end

---@package
---@param spec ozone.Config.PluginSpec
function Build:_install_plugin(spec)
    if spec.source.kind == "git" then
        install_git_plugin(spec)
        return
    elseif spec.source.kind == "path" then
        return
    end
    error(("unsupported source kind: %s"):format(spec.source.kind))
end

---@param config ozone.Config
---@return string? path
function Build:generate_script(config)
    local script = Script.new()
    local queue = Queue.Counting.new()

    for name, spec in pairs(config:get_plugins()) do
        local callback = queue:callback()
        coro.pspawn(function(success, ...)
            if success then
                callback(true, ...)
            else
                callback(false, ("plugin %q %s"):format(name, ...))
            end
        end, function()
            self:_install_plugin(spec)
            local path_is_dir = fs.is_dir(spec.path)
            local has_after_dir = path_is_dir and fs.is_dir(spec.path .. "/after") or false
            return {
                name = name,
                spec = spec,
                path_is_dir = path_is_dir,
                has_after_dir = has_after_dir,
            }
        end)
    end

    local results = {} ---@type table<string, ozone.Build.PluginBuildResult>

    while not queue:is_completed() do
        local co_success, result_or_err = queue:get()
        if not co_success then
            self:err("%s", result_or_err or "unknown error")
        else
            local result = result_or_err ---@type ozone.Build.PluginBuildResult
            results[result.name] = result
        end
    end

    -- TODO: fix the order of paths in 'runtimepath'
    for name, result in pairs(results) do
        if result.path_is_dir then
            table.insert(script.rtp_prefix, result.spec.path)
            if result.has_after_dir then
                table.insert(script.rtp_suffix, result.spec.path .. "/after")
            end
        elseif result.spec.source.kind == "path" then
            self:err("plugin %q path is not a directory: %s", name, result.spec.path)
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
