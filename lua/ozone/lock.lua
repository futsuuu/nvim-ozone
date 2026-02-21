local fs = require("ozone.x.fs")

local M = {}

---@class ozone.Lock.Plugin
---@field url string
---@field revision string
---@field locked_version? string

---@param lock_path string
---@param message string
---@return string
local function format_read_error(lock_path, message)
    return ("failed to read lock file %s: %s"):format(lock_path, message)
end

---@param plugins table<string, ozone.Lock.Plugin>
---@return string[]
local function sorted_plugin_names(plugins)
    local names = {} ---@type string[]
    for name, _ in pairs(plugins) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

---@return string
function M.path()
    return vim.fs.joinpath(vim.fn.stdpath("config"), "ozone-lock.json")
end

---@return table<string, ozone.Lock.Plugin>? plugins
---@return string? err
function M.read()
    local lock_path = M.path()
    if not fs.exists(lock_path) then
        return {}, nil
    end

    local data, read_err = fs.read_file(lock_path)
    if not data then
        return nil, format_read_error(lock_path, read_err or "unknown error")
    end

    local ok, decoded_or_err = pcall(vim.json.decode, data)
    if not ok then
        return nil, format_read_error(lock_path, tostring(decoded_or_err))
    end

    if type(decoded_or_err) ~= "table" then
        return nil, format_read_error(lock_path, "top-level object must be a table")
    end

    local raw_plugins = decoded_or_err.plugins
    if raw_plugins == nil then
        return {}, nil
    end
    if type(raw_plugins) ~= "table" then
        return nil, format_read_error(lock_path, "field 'plugins' must be a table")
    end

    local plugins = {} ---@type table<string, ozone.Lock.Plugin>
    for name, raw_entry in pairs(raw_plugins) do
        if type(name) ~= "string" then
            return nil, format_read_error(lock_path, "plugin name must be a string")
        end
        if type(raw_entry) ~= "table" then
            return nil, format_read_error(lock_path, ("plugin %q entry must be a table"):format(name))
        end

        local url = raw_entry.url
        local revision = raw_entry.revision
        local locked_version = raw_entry.locked_version

        if type(url) ~= "string" or url == "" then
            return nil, format_read_error(lock_path, ("plugin %q field 'url' must be a non-empty string"):format(name))
        end
        if type(revision) ~= "string" or revision == "" then
            return nil,
                format_read_error(lock_path, ("plugin %q field 'revision' must be a non-empty string"):format(name))
        end
        if locked_version ~= nil and (type(locked_version) ~= "string" or locked_version == "") then
            return nil,
                format_read_error(
                    lock_path,
                    ("plugin %q field 'locked_version' must be a non-empty string"):format(name)
                )
        end

        plugins[name] = {
            url = url,
            revision = revision,
            locked_version = locked_version,
        }
    end

    return plugins, nil
end

---@param plugins table<string, ozone.Lock.Plugin>
---@return boolean? success
---@return string? err
function M.write(plugins)
    local lock_path = M.path()
    local lock_dir = vim.fs.dirname(lock_path)
    if not lock_dir then
        return nil, ("failed to determine lock file directory: %s"):format(lock_path)
    end

    local created, create_err = fs.create_dir_all(lock_dir)
    if not created then
        return nil, ("failed to create lock file directory %s: %s"):format(lock_dir, create_err or "unknown error")
    end

    local serialized_plugins = {}
    for _, name in ipairs(sorted_plugin_names(plugins)) do
        local plugin = plugins[name]
        serialized_plugins[name] = {
            url = plugin.url,
            revision = plugin.revision,
            locked_version = plugin.locked_version,
        }
    end

    local ok, encoded_or_err = pcall(vim.json.encode, {
        plugins = serialized_plugins,
    })
    if not ok then
        return nil, ("failed to encode lock file %s: %s"):format(lock_path, tostring(encoded_or_err))
    end

    local wrote, write_err = fs.write_file(lock_path, encoded_or_err .. "\n")
    if not wrote then
        return nil, ("failed to write lock file %s: %s"):format(lock_path, write_err or "unknown error")
    end

    return true, nil
end

return M
