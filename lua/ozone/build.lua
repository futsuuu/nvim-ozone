local Queue = require("ozone.x.queue")
local coro = require("ozone.x.coro")
local fs = require("ozone.x.fs")

local Lock = require("ozone.lock")
local Script = require("ozone.script")
local git = require("ozone.git")

---@class ozone.Build
---@field private _errors string[]
---@field private _output_path string
local Build = {}
---@private
Build.__index = Build

---@class ozone.Build.PluginBuildResult
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

---@return nil
function Build:clear_errors()
    self._errors = {}
end

---@param source ozone.Config.PluginSource.Git
---@return string? checkout_target
local function resolve_checkout_target(source)
    return source.revision or source.version
end

---@param spec ozone.Config.PluginSpec
local function install_git_plugin(spec)
    local source = spec.source
    if source.kind ~= "git" then
        return
    end
    if fs.exists(spec.path) then
        if fs.is_dir(spec.path) then
            local checkout_target = resolve_checkout_target(source)
            if checkout_target then
                local checkout_success, checkout_err = git.checkout(spec.path, checkout_target)
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

    local checkout_target = resolve_checkout_target(source)
    if checkout_target then
        local checkout_success, checkout_err = git.checkout(spec.path, checkout_target)
        if not checkout_success then
            error(checkout_err or "checkout failed", 0)
        end
    end
end

---@param spec ozone.Config.PluginSpec
---@return boolean? success
---@return string? err
local function clone_git_plugin_if_needed(spec)
    local source = spec.source
    if source.kind ~= "git" then
        return true, nil
    end

    if fs.exists(spec.path) then
        if fs.is_dir(spec.path) then
            return true, nil
        end
        return nil, ("install path exists and is not a directory: %s"):format(spec.path)
    end

    local clone_success, clone_err = git.clone(source.url, spec.path)
    if not clone_success then
        return nil, clone_err or "clone failed"
    end

    return true, nil
end

---@param spec ozone.Config.PluginSpec
---@return ozone.Config.LockPluginSpec? lock_spec
---@return string? err
local function resolve_latest_lock_plugin(spec)
    local source = spec.source
    if source.kind ~= "git" then
        return nil, nil
    end

    local cloned, clone_err = clone_git_plugin_if_needed(spec)
    if not cloned then
        return nil, clone_err
    end

    local fetched, fetch_err = git.fetch(spec.path)
    if not fetched then
        return nil, fetch_err
    end

    local revision = nil ---@type string?
    local revision_err = nil ---@type string?
    if source.version then
        revision, revision_err = git.resolve_version_revision(spec.path, source.version)
    else
        revision, revision_err = git.remote_head_revision(spec.path)
    end
    if not revision then
        return nil, revision_err
    end

    return {
        url = source.url,
        version = source.version,
        revision = revision,
    }, nil
end

---@param self ozone.Build
---@param warnings string[]
---@return nil
local function report_warnings(self, warnings)
    for _, message in ipairs(warnings) do
        self:err("warning: %s", message)
    end
end

---@param config ozone.Config
---@param plugin_names_in_load_order string[]
---@return nil
function Build:_write_lock_file(config, plugin_names_in_load_order)
    local plugins = config:get_plugins()
    local lock = Lock.default()

    for _, name in ipairs(plugin_names_in_load_order) do
        local spec = plugins[name]
        if spec and spec.source.kind == "git" then
            if fs.is_dir(spec.path) then
                local revision, revision_err = git.revision(spec.path)
                if not revision then
                    self:err(
                        "plugin %q failed to resolve installed revision at %s: %s",
                        name,
                        spec.path,
                        revision_err or "unknown error"
                    )
                else
                    lock.plugins[name] = {
                        url = spec.source.url,
                        version = spec.source.version,
                        revision = revision,
                    }
                end
            end
        end
    end

    local wrote, write_err = config:write_lock_file(lock)
    if not wrote then
        self:err("%s", write_err or "failed to write lock file")
    end
end

---@param config ozone.Config
---@return nil
function Build:update_lock_file(config)
    local plugins = config:get_plugins()
    local plugin_names_in_load_order, warnings = config:get_plugin_names_in_load_order()
    report_warnings(self, warnings)

    local lock = config:read_lock_file()
    for _, name in ipairs(plugin_names_in_load_order) do
        local spec = plugins[name]
        if spec and spec.source.kind == "git" then
            local lock_spec, lock_plugin_err = resolve_latest_lock_plugin(spec)
            if lock_spec then
                lock.plugins[name] = lock_spec
            else
                self:err("plugin %q failed to update lock data: %s", name, lock_plugin_err or "unknown error")
            end
        end
    end

    local wrote, write_err = config:write_lock_file(lock)
    if not wrote then
        self:err("%s", write_err or "failed to write lock file")
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

---@param path string
---@param pattern string
---@return string[]
local function globpath(path, pattern)
    return vim.fn.globpath(path, pattern, false, true)
end

---@param config ozone.Config
---@return string? path
function Build:generate_script(config)
    local script = Script.new()
    local queue = Queue.Counting.new()
    local plugins = config:get_plugins()

    for _, spec in pairs(plugins) do
        local callback = queue:callback()
        coro.pspawn(function(success, ...)
            if success then
                callback(true, ...)
            else
                callback(false, ("plugin %q %s"):format(spec.name, ...))
            end
        end, function()
            self:_install_plugin(spec)
            local path_is_dir = fs.is_dir(spec.path)
            local has_after_dir = path_is_dir and fs.is_dir(spec.path .. "/after") or false
            return {
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
            results[result.spec.name] = result
        end
    end

    local plugin_names_in_load_order, warnings = config:get_plugin_names_in_load_order()
    report_warnings(self, warnings)

    do
        local default_rtp = vim.opt.runtimepath:get() ---@type string[]
        for _, path in ipairs(default_rtp) do
            if fs.is_dir(path) then
                table.insert(script.default_rtdirs, {
                    path = vim.fs.abspath(path),
                    plugin_files = globpath(path, "plugin/**/*.{vim,lua}"),
                    ftdetect_files = globpath(path, "ftdetect/*.{vim,lua}"),
                })
            end
        end
    end

    for _, name in ipairs(plugin_names_in_load_order) do
        local result = results[name]
        if result ~= nil then
            if result.path_is_dir then
                table.insert(script.rtdirs, {
                    path = result.spec.path,
                    plugin_files = globpath(result.spec.path, "plugin/**/*.{vim,lua}"),
                    ftdetect_files = globpath(result.spec.path, "ftdetect/*.{vim,lua}"),
                })
                if result.has_after_dir then
                    table.insert(script.after_rtdirs, 1, {
                        path = result.spec.path .. "/after",
                        plugin_files = globpath(result.spec.path .. "/after", "plugin/**/*.{vim,lua}"),
                        ftdetect_files = globpath(result.spec.path .. "/after", "ftdetect/*.{vim,lua}"),
                    })
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
        self:err("failed to create output directory %s: %s", output_dir, create_dir_err or "unknown error")
        return nil
    end

    local wrote, write_err = fs.write_file(self._output_path, script:tostring())
    if not wrote then
        self:err("failed to write generated script %s: %s", self._output_path, write_err or "unknown error")
        return nil
    end

    self:_write_lock_file(config, plugin_names_in_load_order)

    return self._output_path
end

return Build
