local buffer = require("string.buffer")

local fs = require("ozone.x.fs")

---@class ozone.Lock
---@field plugins table<string, ozone.Config.LockPluginSpec>
local Lock = {}
---@private
Lock.__index = Lock

---@return ozone.Lock
function Lock.default()
    return setmetatable({
        plugins = {},
    }, Lock)
end

---@param path string
---@return ozone.Lock
function Lock.read(path)
    if not fs.exists(path) then
        return Lock.default()
    end
    local data = assert(fs.read_file(path))
    return Lock.decode(data)
end

---@param path string
---@return boolean? success, string? err
function Lock:write(path)
    local lock_dir = assert(vim.fs.dirname(path))
    local created, create_dir_err = fs.create_dir_all(lock_dir)
    if not created then
        return nil, create_dir_err
    end
    return fs.write_file(path, self:encode())
end

---@param data string
---@return ozone.Lock
function Lock.decode(data)
    local decoded = vim.json.decode(data, { luanil = { object = true } }) --[[@as ozone.Lock]]
    if decoded.plugins == nil then
        decoded.plugins = {}
    end
    return setmetatable(decoded, Lock)
end

---@generic K
---@param t { [K]: unknown }
---@return K[]
local function sorted_keys(t)
    local keys = {}
    ---@diagnostic disable-next-line: no-unknown
    for key in pairs(t) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

---@return string
function Lock:encode()
    local names = sorted_keys(self.plugins)
    if #names == 0 then
        return '{ "plugins": {} }\n'
    end

    local buf = buffer.new():put("{")

    buf:put('\n  "plugins": {')
    for i, name in ipairs(names) do
        local plugin = self.plugins[name]
        buf:putf("\n    %s: {", vim.json.encode(name))
            :putf('\n      "url": %s', vim.json.encode(plugin.url))
            :putf(',\n      "version": %s', vim.json.encode(plugin.version))
            :putf(',\n      "revision": %s', vim.json.encode(plugin.revision))
            :putf("\n    }%s", i == #names and "" or ",")
    end
    buf:put("\n  }")

    buf:put("\n}\n")
    return buf:tostring()
end

return Lock
