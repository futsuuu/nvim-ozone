---@class ozone.Config
---@field private _plugins table<string, ozone.Config.PluginSpec>
---@field private _plugin_name_counts table<string, integer>
---@field private _install_root string
local Config = {}
---@private
Config.__index = Config

---@class ozone.Config.PluginSpec
---@field path string
---@field source ozone.Config.PluginSource

---@alias ozone.Config.PluginSource
---| ozone.Config.PluginSource.Path
---| ozone.Config.PluginSource.Git
---@class ozone.Config.PluginSource.Path
---@field kind "path"
---@class ozone.Config.PluginSource.Git
---@field kind "git"
---@field url string
---@field version? string

---@return self
function Config.new()
    return setmetatable({
        _plugins = {},
        _plugin_name_counts = {},
        _install_root = vim.fs.joinpath(vim.fn.stdpath("data"), "ozone", "_"),
    }, Config)
end

---@return nil
function Config:load()
    -- TODO: evaluate all build scripts
    require("_build")
end

---@return table<string, ozone.Config.PluginSpec>
function Config:get_plugins()
    return self._plugins
end

---@package
---@param name string
---@return string
function Config:_default_plugin_path(name)
    return vim.fs.joinpath(self._install_root, name)
end

---@param name string
---@param spec ozone.Build.PluginSpec
---@return ozone.Config.PluginSpec
function Config:add_plugin(name, spec)
    if type(name) ~= "string" then
        error(("invalid type of plugin name (string expected, got %s)"):format(type(name)))
    elseif name:match("^[%w_.-]+$") == nil then
        error(
            ('invalid plugin name (only letters, digits, "_", ".", and "-" are allowed, got %q)'):format(
                name
            )
        )
    end
    if type(spec) ~= "table" then
        error(("invalid type of 'specs.%s' (table expected, got %s)"):format(name, type(spec)))
    end

    if spec.path ~= nil then
        if type(spec.path) ~= "string" then
            error(
                ("invalid type of '%s.path' (string expected, got %s)"):format(
                    name,
                    type(spec.path)
                )
            )
        elseif spec.path == "" then
            error(("invalid '%s.path' (non-empty string expected)"):format(name))
        end
        spec.path = vim.fs.normalize(spec.path)
    end
    if spec.url ~= nil then
        if type(spec.url) ~= "string" then
            error(
                ("invalid type of '%s.url' (string expected, got %s)"):format(name, type(spec.url))
            )
        elseif spec.url == "" then
            error(("invalid '%s.url' (non-empty string expected)"):format(name))
        end
    end
    if spec.version ~= nil then
        if type(spec.version) ~= "string" then
            error(
                ("invalid type of '%s.version' (string expected, got %s)"):format(
                    name,
                    type(spec.version)
                )
            )
        elseif spec.version == "" then
            error(("invalid '%s.version' (non-empty string expected)"):format(name))
        end
    end

    if spec.version ~= nil and spec.url == nil then
        error(("'%s.version' requires '%s.url'"):format(name, name))
    end

    if spec.path == nil and spec.url == nil then
        error(("'%s.path' or '%s.url' must be set"):format(name, name))
    end

    local name_count = (self._plugin_name_counts[name] or 0) + 1
    self._plugin_name_counts[name] = name_count
    if name_count > 1 then
        self._plugins[name] = nil
        error(("plugin name %q is duplicated (definition #%d)"):format(name, name_count))
    end

    local resolved_spec = nil ---@type ozone.Config.PluginSpec?
    if spec.url then
        resolved_spec = {
            path = spec.path or self:_default_plugin_path(name),
            source = {
                kind = "git",
                url = spec.url,
                version = spec.version,
            },
        }
    else
        local plugin_path = assert(spec.path)
        resolved_spec = {
            path = plugin_path,
            source = {
                kind = "path",
            },
        }
    end

    self._plugins[name] = resolved_spec
    return resolved_spec
end

return Config
