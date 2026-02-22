local lock = require("ozone.lock")

---@class ozone.Config
---@field private _plugins table<string, ozone.Config.PluginSpec>
---@field private _plugin_name_counts table<string, integer>
---@field private _install_root string
---@field private _dep_names_by_spec table<ozone.Config.PluginSpec, string[]>
---@field private _lock_plugins table<string, ozone.Config.LockPluginSpec>
local Config = {}
---@private
Config.__index = Config

---@class ozone.Config.PluginSpec
---@field name string
---@field path string
---@field source ozone.Config.PluginSource
---@field deps self[]

---@alias ozone.Config.PluginSource
---| ozone.Config.PluginSource.Path
---| ozone.Config.PluginSource.Git
---@class ozone.Config.PluginSource.Path
---@field kind "path"
---@class ozone.Config.PluginSource.Git
---@field kind "git"
---@field url string
---@field version? string
---@field revision? string

---@class ozone.Config.LockPluginSpec
---@field url string
---@field version? string
---@field revision? string

---@return self
function Config.new()
    return setmetatable({
        _plugins = {},
        _plugin_name_counts = {},
        _install_root = vim.fs.joinpath(vim.fn.stdpath("data"), "ozone", "_"),
        _dep_names_by_spec = {},
        _lock_plugins = {},
    }, Config)
end

---@return nil
function Config:load()
    self._lock_plugins = lock.read()
    -- TODO: evaluate all build scripts
    require("_build")
end

---@return table<string, ozone.Config.PluginSpec>
function Config:get_plugins()
    return self._plugins
end

---@private
---@return string[]
function Config:_sorted_plugin_names()
    local names = {} ---@type string[]
    for name, _ in pairs(self._plugins) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

---@private
---@return string[] warnings
function Config:_resolve_plugin_deps()
    local warnings = {} ---@type string[]

    -- `spec.deps` stores spec references, so string names are resolved after all
    -- plugins have been registered.
    for _, name in ipairs(self:_sorted_plugin_names()) do
        local spec = assert(self._plugins[name])
        local dep_specs = {} ---@type ozone.Config.PluginSpec[]
        local seen_dep_specs = {} ---@type table<ozone.Config.PluginSpec, boolean>
        for _, dep_name in ipairs(self._dep_names_by_spec[spec] or {}) do
            local dep_spec = self._plugins[dep_name]
            if dep_spec == nil then
                table.insert(warnings, ("plugin %q depends on undefined plugin %q"):format(spec.name, dep_name))
            elseif not seen_dep_specs[dep_spec] then
                seen_dep_specs[dep_spec] = true
                table.insert(dep_specs, dep_spec)
            end
        end
        table.sort(dep_specs, function(left, right)
            return left.name < right.name
        end)
        spec.deps = dep_specs
    end

    return warnings
end

---@return string[] ordered_names
---@return string[] warnings
function Config:get_plugin_names_in_load_order()
    local warnings = self:_resolve_plugin_deps()

    local ordered_names = {} ---@type string[]
    local spec_states = {} ---@type table<ozone.Config.PluginSpec, "visiting" | "visited">
    -- Deduplicate warnings per edge when the same cycle is encountered again.
    local warned_edges = {} ---@type table<string, boolean>

    ---@param spec ozone.Config.PluginSpec
    ---@return nil
    local function visit(spec)
        local state = spec_states[spec]
        if state == "visited" then
            return
        elseif state == "visiting" then
            return
        end

        -- DFS with 3-state markers builds topological order while allowing
        -- cycle detection without aborting the build.
        spec_states[spec] = "visiting"

        for _, dep_spec in ipairs(spec.deps) do
            local dep_name = dep_spec.name
            local dep_state = spec_states[dep_spec]
            if dep_state == "visiting" then
                local edge_key = spec.name .. "->" .. dep_name
                if not warned_edges[edge_key] then
                    warned_edges[edge_key] = true
                    table.insert(
                        warnings,
                        ("plugin %q has circular dependency on %q; continuing with best-effort order"):format(
                            spec.name,
                            dep_name
                        )
                    )
                end
            else
                visit(dep_spec)
            end
        end

        spec_states[spec] = "visited"
        table.insert(ordered_names, spec.name)
    end

    for _, name in ipairs(self:_sorted_plugin_names()) do
        local spec = self._plugins[name]
        if spec ~= nil then
            visit(spec)
        end
    end

    return ordered_names, warnings
end

---@package
---@param name string
---@return string
function Config:_default_plugin_path(name)
    return vim.fs.joinpath(self._install_root, name)
end

---@private
---@param name string
---@param url string
---@param version? string
---@return string? revision
function Config:_resolve_locked_revision(name, url, version)
    local lock_plugin = self._lock_plugins[name]
    if lock_plugin == nil then
        return nil
    end

    local is_same_source = lock_plugin.url == url
    local is_same_version = lock_plugin.version == version
    if is_same_source and is_same_version then
        return lock_plugin.revision
    end

    return nil
end

---@param name string
---@param spec ozone.PluginSpec
---@return ozone.Config.PluginSpec
function Config:add_plugin(name, spec)
    if type(name) ~= "string" then
        error(("invalid type of plugin name (string expected, got %s)"):format(type(name)))
    elseif name:match("^[%w_.-]+$") == nil then
        error(('invalid plugin name (only letters, digits, "_", ".", and "-" are allowed, got %q)'):format(name))
    end
    if type(spec) ~= "table" then
        error(("invalid type of 'specs.%s' (table expected, got %s)"):format(name, type(spec)))
    end

    local dep_names = {} ---@type string[]
    if spec.deps ~= nil then
        if type(spec.deps) ~= "table" then
            error(("invalid type of '%s.deps' (string[] expected, got %s)"):format(name, type(spec.deps)))
        elseif not vim.islist(spec.deps) then
            error(("invalid '%s.deps' (string[] expected)"):format(name))
        end
        for i, dep_name in ipairs(spec.deps) do
            if type(dep_name) ~= "string" then
                error(("invalid type of '%s.deps[%d]' (string expected, got %s)"):format(name, i, type(dep_name)))
            elseif dep_name == "" then
                error(("invalid '%s.deps[%d]' (non-empty string expected)"):format(name, i))
            elseif dep_name:match("^[%w_.-]+$") == nil then
                error(
                    ([[invalid '%s.deps[%d]' (only letters, digits, "_", ".", and "-" are allowed, got %q)]]):format(
                        name,
                        i,
                        dep_name
                    )
                )
            end
            table.insert(dep_names, dep_name)
        end
    end

    if spec.path ~= nil then
        if type(spec.path) ~= "string" then
            error(("invalid type of '%s.path' (string expected, got %s)"):format(name, type(spec.path)))
        elseif spec.path == "" then
            error(("invalid '%s.path' (non-empty string expected)"):format(name))
        end
        spec.path = vim.fs.normalize(spec.path)
    end
    if spec.url ~= nil then
        if type(spec.url) ~= "string" then
            error(("invalid type of '%s.url' (string expected, got %s)"):format(name, type(spec.url)))
        elseif spec.url == "" then
            error(("invalid '%s.url' (non-empty string expected)"):format(name))
        end
    end
    if spec.version ~= nil then
        if type(spec.version) ~= "string" then
            error(("invalid type of '%s.version' (string expected, got %s)"):format(name, type(spec.version)))
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
        local existing_spec = self._plugins[name]
        if existing_spec ~= nil then
            self._dep_names_by_spec[existing_spec] = nil
        end
        self._plugins[name] = nil
        error(("plugin name %q is duplicated (definition #%d)"):format(name, name_count))
    end

    local resolved_spec = nil ---@type ozone.Config.PluginSpec?
    if spec.url then
        local source_url = assert(spec.url)
        local source_version = spec.version
        resolved_spec = {
            name = name,
            path = spec.path or self:_default_plugin_path(name),
            source = {
                kind = "git",
                url = source_url,
                version = source_version,
                revision = self:_resolve_locked_revision(name, source_url, source_version),
            },
            deps = {},
        }
    else
        local plugin_path = assert(spec.path)
        resolved_spec = {
            name = name,
            path = plugin_path,
            source = {
                kind = "path",
            },
            deps = {},
        }
    end

    self._plugins[name] = resolved_spec
    self._dep_names_by_spec[resolved_spec] = dep_names
    return resolved_spec
end

return Config
