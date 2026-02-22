local buffer = require("string.buffer")

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

---@param plugins table<string, ozone.Lock.Plugin>
---@return string
local function format_lock_file_json(plugins)
    local names = sorted_plugin_names(plugins)
    if #names == 0 then
        return '{ "plugins": {} }\n'
    end
    local buf = buffer.new()

    buf:put("{")

    buf:put('\n  "plugins": {')
    for i, name in ipairs(names) do
        local plugin = plugins[name]
        buf:putf("\n    %s: {", vim.json.encode(name))
        buf:putf('\n      "url": %s', vim.json.encode(plugin.url))
        buf:putf(',\n      "revision": %s', vim.json.encode(plugin.revision))
        if plugin.locked_version then
            buf:putf(',\n      "locked_version": %s', vim.json.encode(plugin.locked_version))
        end
        buf:putf("\n    }%s", i == #names and "" or ",")
    end
    buf:put("\n  }")

    buf:put("\n}\n")

    return buf:tostring()
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
    local plugins = {} ---@type table<string, ozone.Lock.Plugin>
    for name, plugin in pairs(decoded.plugins) do
        plugins[name] = {
            url = plugin.url,
            revision = plugin.revision,
            locked_version = plugin.locked_version,
        }
    end
    return plugins
end

---@param plugins table<string, ozone.Lock.Plugin>
---@return boolean? success, string? err
function M.write(plugins)
    local lock_path = M.path()
    local lock_dir = assert(vim.fs.dirname(lock_path))
    local created, create_dir_err = fs.create_dir_all(lock_dir)
    if not created then
        return nil, create_dir_err
    end

    local encoded = format_lock_file_json(plugins)
    return fs.write_file(lock_path, encoded)
end

return M
