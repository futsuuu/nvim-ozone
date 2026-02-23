local Queue = require("ozone.x.queue")
local coro = require("ozone.x.coro")
local fs = require("ozone.x.fs")

local Fetcher = require("ozone.fetcher")
local GitFetcher = require("ozone.fetcher.git")
local Lockfile = require("ozone.lockfile")
local Script = require("ozone.script")

local git_fetcher = GitFetcher.new()

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

---@class ozone.Build.LockfileUpdateResult
---@field name string
---@field lockfile_spec ozone.Config.LockfilePluginSpec?
---@field err string?

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

---@param _opts ozone.CleanOpts
---@return nil
function Build:clean(_opts)
    assert(vim.uv.fs_unlink(self._output_path))
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

---@param spec ozone.Config.PluginSpec
local function install_git_plugin(spec)
    local source = spec.source
    if source.kind ~= "git" then
        return
    end

    local installed, install_err = git_fetcher:install(source, spec.path)
    if not installed then
        error(Fetcher.format_error(install_err, "install failed"), 0)
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

    local cloned, clone_err = git_fetcher:ensure_cloned(source, spec.path)
    if not cloned then
        return nil, Fetcher.format_error(clone_err, "clone failed")
    end

    return true, nil
end

---@param spec ozone.Config.PluginSpec
---@return ozone.Config.LockfilePluginSpec? lockfile_spec
---@return string? err
local function resolve_latest_lockfile_plugin(spec)
    local source = spec.source
    if source.kind ~= "git" then
        return nil, nil
    end

    local cloned, clone_err = clone_git_plugin_if_needed(spec)
    if not cloned then
        return nil, clone_err
    end

    local fetched, fetch_err = git_fetcher:fetch(spec.path)
    if not fetched then
        return nil, Fetcher.format_error(fetch_err, "fetch failed")
    end

    local revision = nil ---@type string?
    local revision_err = nil ---@type ozone.Fetcher.Error?
    revision, revision_err = git_fetcher:resolve_revision(source, spec.path)
    if not revision then
        return nil, Fetcher.format_error(revision_err, "failed to resolve revision")
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
function Build:_write_lockfile(config, plugin_names_in_load_order)
    local plugins = config:get_plugins()
    local lockfile = Lockfile.default()

    for _, name in ipairs(plugin_names_in_load_order) do
        local spec = plugins[name]
        if spec and spec.source.kind == "git" then
            if fs.is_dir(spec.path) then
                local revision, revision_err = git_fetcher:revision(spec.path)
                if revision == nil then
                    self:err(
                        "plugin %q failed to resolve installed revision at %s: %s",
                        name,
                        spec.path,
                        Fetcher.format_error(revision_err)
                    )
                else
                    lockfile.plugins[name] = {
                        url = spec.source.url,
                        version = spec.source.version,
                        revision = revision,
                    }
                end
            end
        end
    end

    local wrote, write_err = config:write_lockfile(lockfile)
    if not wrote then
        self:err("%s", write_err or "failed to write lock file")
    end
end

---@param config ozone.Config
---@return nil
function Build:update_lockfile(config)
    local plugins = config:get_plugins()
    local plugin_names_in_load_order, warnings = config:get_plugin_names_in_load_order()
    report_warnings(self, warnings)

    local lockfile = config:read_lockfile()
    local queue = Queue.Counting.new()

    for _, name in ipairs(plugin_names_in_load_order) do
        local spec = plugins[name]
        if spec and spec.source.kind == "git" then
            coro.pspawn(queue:callback(), function()
                assert(coro.context()).data = name
                local lockfile_spec, lockfile_plugin_err = resolve_latest_lockfile_plugin(spec)
                return {
                    name = name,
                    lockfile_spec = lockfile_spec,
                    err = lockfile_plugin_err,
                }
            end)
        end
    end

    while not queue:is_completed() do
        local cx, co_success, result_or_err = queue:get()
        if not co_success then
            self:err("plugin %q %s", cx.data, result_or_err or "unknown error")
        else
            local result = result_or_err ---@type ozone.Build.LockfileUpdateResult
            if result.lockfile_spec then
                lockfile.plugins[result.name] = result.lockfile_spec
            else
                self:err("plugin %q failed to update lock data: %s", result.name, result.err or "unknown error")
            end
        end
    end

    local wrote, write_err = config:write_lockfile(lockfile)
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
        coro.pspawn(queue:callback(), function()
            assert(coro.context()).data = spec.name
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
        local cx, co_success, result_or_err = queue:get()
        if not co_success then
            self:err("plugin %q %s", cx.data, result_or_err or "unknown error")
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

    self:_write_lockfile(config, plugin_names_in_load_order)

    return self._output_path
end

return Build
