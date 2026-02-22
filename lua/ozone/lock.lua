local buffer = require("string.buffer")

local Config = require("ozone.config")
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

---@param plugins table<string, ozone.Config.PluginSpec>
---@return string[]
local function sorted_git_plugin_names(plugins)
    local names = {} ---@type string[]
    for name, spec in pairs(plugins) do
        if spec.source.kind == "git" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

---@param config ozone.Config
---@return string
local function format_lock_file_json(config)
    local plugins = config:get_plugins()
    local names = sorted_git_plugin_names(plugins)
    if #names == 0 then
        return '{ "plugins": {} }\n'
    end
    local buf = buffer.new()

    buf:put("{")

    buf:put('\n  "plugins": {')
    for i, name in ipairs(names) do
        local spec = assert(plugins[name])
        local source = spec.source
        if source.kind ~= "git" then
            error(("plugin %q source must be git in lock config"):format(name))
        end
        buf:putf("\n    %s: {", vim.json.encode(name))
        buf:putf('\n      "url": %s', vim.json.encode(source.url))
        if source.version then
            buf:putf(',\n      "version": %s', vim.json.encode(source.version))
        end
        if source.revision then
            buf:putf(',\n      "revision": %s', vim.json.encode(source.revision))
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

---@return ozone.Config
function M.read()
    local lock_config = Config.new()
    local lock_path = M.path()
    if not fs.exists(lock_path) then
        return lock_config
    end

    local data = assert(fs.read_file(lock_path))
    local decoded = vim.json.decode(data) --[[@as ozone.lock.DecodedFile]]
    for name, plugin in pairs(decoded.plugins) do
        lock_config:add_locked_plugin(name, {
            url = plugin.url,
            version = normalize_optional_string(plugin.version),
            revision = normalize_optional_string(plugin.revision),
        })
    end
    return lock_config
end

---@param config ozone.Config
---@return boolean? success, string? err
function M.write(config)
    local lock_path = M.path()
    local lock_dir = assert(vim.fs.dirname(lock_path))
    local created, create_dir_err = fs.create_dir_all(lock_dir)
    if not created then
        return nil, create_dir_err
    end

    local encoded = format_lock_file_json(config)
    return fs.write_file(lock_path, encoded)
end

return M
