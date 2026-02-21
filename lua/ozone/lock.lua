local fs = require("ozone.x.fs")

local M = {}

---@class ozone.Lock.Plugin
---@field url string
---@field revision string
---@field locked_version? string

---@class ozone.Lock.File
---@field plugins table<string, ozone.Lock.Plugin>

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

---@return table<string, ozone.Lock.Plugin> plugins
function M.read()
    local lock_path = M.path()
    if not fs.exists(lock_path) then
        return {}
    end

    local data = assert(fs.read_file(lock_path))
    local decoded = vim.json.decode(data) --[[@as ozone.Lock.File]]
    return decoded.plugins
end

---@param plugins table<string, ozone.Lock.Plugin>
---@return nil
function M.write(plugins)
    local lock_path = M.path()
    local lock_dir = assert(vim.fs.dirname(lock_path))
    assert(fs.create_dir_all(lock_dir))

    local serialized_plugins = {} ---@type table<string, ozone.Lock.Plugin>
    for _, name in ipairs(sorted_plugin_names(plugins)) do
        local plugin = plugins[name]
        serialized_plugins[name] = {
            url = plugin.url,
            revision = plugin.revision,
            locked_version = plugin.locked_version,
        }
    end

    local encoded = vim.json.encode({
        plugins = serialized_plugins,
    })
    assert(fs.write_file(lock_path, encoded .. "\n"))
end

return M
