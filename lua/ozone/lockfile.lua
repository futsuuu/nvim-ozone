local buffer = require("string.buffer")

local fs = require("ozone.x.fs")

---@class ozone.Lockfile
---@field plugins table<string, ozone.Config.LockfilePluginSpec>
local Lockfile = {}
---@private
Lockfile.__index = Lockfile

---@return ozone.Lockfile
function Lockfile.default()
    return setmetatable({
        plugins = {},
    }, Lockfile)
end

---@param path string
---@return ozone.Lockfile
function Lockfile.read(path)
    if not fs.exists(path) then
        return Lockfile.default()
    end
    local data = assert(fs.read_file(path))
    return Lockfile.decode(data)
end

---@param path string
---@return boolean? success, string? err
function Lockfile:write(path)
    local lockfile_dir = assert(vim.fs.dirname(path))
    local created, create_dir_err = fs.create_dir_all(lockfile_dir)
    if not created then
        return nil, create_dir_err
    end
    return fs.write_file(path, self:encode())
end

---@param data string
---@return ozone.Lockfile
function Lockfile.decode(data)
    local decoded = vim.json.decode(data, { luanil = { object = true } }) --[[@as ozone.Lockfile]]
    if decoded.plugins == nil then
        decoded.plugins = {}
    end
    return setmetatable(decoded, Lockfile)
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
function Lockfile:encode()
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

return Lockfile
