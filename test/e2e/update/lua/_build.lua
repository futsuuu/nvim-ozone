local ozone = require("ozone")

local helper = require("test.helper")

local META_PATH = vim.fs.joinpath(vim.fn.stdpath("state"), "update-meta.json")
local REMOVE_REMOVED_FLAG_PATH = vim.fs.joinpath(vim.fn.stdpath("state"), "update-remove-removed")

---@class test.e2e.update.Meta
---@field tracked_repo string
---@field tracked_rev string
---@field versioned_repo string
---@field versioned_rev string
---@field removed_repo string

---@param path string
---@return table?
local function read_json(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local data = assert(file:read("*a"))
    assert(file:close())
    local ok, value_or_err = pcall(vim.json.decode, data)
    assert(ok, value_or_err)
    return value_or_err
end

---@param path string
---@param value table
---@return nil
local function write_json(path, value)
    local dir_path = assert(vim.fs.dirname(path))
    assert(1 == vim.fn.mkdir(dir_path, "p"))
    local file = assert(io.open(path, "w"))
    assert(file:write(vim.json.encode(value)))
    assert(file:close())
end

---@param cmd string[]
---@return nil
local function run_system(cmd)
    local output = vim.fn.system(cmd)
    assert(vim.v.shell_error == 0, output)
end

---@return test.e2e.update.Meta
local function ensure_meta()
    local meta = read_json(META_PATH)
    if meta then
        return meta --[[@as test.e2e.update.Meta]]
    end

    local tracked_repo = helper.git_repo({
        ["plugin/tracked.lua"] = [[
vim.g.update_tracked_value = "v1"
]],
    })

    local versioned_repo = helper.git_repo({
        ["plugin/versioned.lua"] = [[
vim.g.update_versioned_value = "v1"
]],
    })
    run_system({ "git", "-C", versioned_repo, "tag", "v1" })
    helper.git_commit(versioned_repo, {
        ["plugin/versioned.lua"] = [[
vim.g.update_versioned_value = "v2"
]],
    })

    local removed_repo = helper.git_repo({
        ["plugin/removed.lua"] = [[
vim.g.update_removed_value = "present"
]],
    })

    meta = {
        tracked_repo = tracked_repo,
        tracked_rev = helper.git_rev(tracked_repo),
        versioned_repo = versioned_repo,
        versioned_rev = helper.git_rev(versioned_repo, "v1"),
        removed_repo = removed_repo,
    }
    write_json(META_PATH, meta)
    return meta --[[@as test.e2e.update.Meta]]
end

local meta = ensure_meta()

local specs = {
    tracked = {
        url = meta.tracked_repo,
    },
    versioned = {
        url = meta.versioned_repo,
        version = "v1",
    },
} ---@type table<string, ozone.PluginSpec>

if vim.uv.fs_stat(REMOVE_REMOVED_FLAG_PATH) == nil then
    specs.removed = {
        url = meta.removed_repo,
    }
end

ozone.add(specs)
