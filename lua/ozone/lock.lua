local buffer = require("string.buffer")

local fs = require("ozone.x.fs")

local M = {}

---@class ozone.lock.DecodedFile
---@field plugins table<string, ozone.Config.LockPluginSpec>

---@param value any
---@return string?
local function normalize_optional_string(value)
    if value == nil or value == vim.NIL then
        return nil
    end
    return value --[[@as string]]
end

---@param plugins table<string, ozone.Config.LockPluginSpec>
---@return string[]
local function sorted_plugin_names(plugins)
    local names = {} ---@type string[]
    for name, _ in pairs(plugins) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

---@param plugins table<string, ozone.Config.LockPluginSpec>
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
        if plugin.version then
            buf:putf(',\n      "version": %s', vim.json.encode(plugin.version))
        end
        if plugin.revision then
            buf:putf(',\n      "revision": %s', vim.json.encode(plugin.revision))
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

---@return table<string, ozone.Config.LockPluginSpec>
function M.read()
    local lock_path = M.path()
    if not fs.exists(lock_path) then
        return {}
    end

    local data = assert(fs.read_file(lock_path))
    local decoded = vim.json.decode(data) --[[@as ozone.lock.DecodedFile]]
    local plugins = {} ---@type table<string, ozone.Config.LockPluginSpec>
    for name, plugin in pairs(decoded.plugins) do
        plugins[name] = {
            url = plugin.url,
            version = normalize_optional_string(plugin.version),
            revision = normalize_optional_string(plugin.revision),
        }
    end
    return plugins
end

---@param plugins table<string, ozone.Config.LockPluginSpec>
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
