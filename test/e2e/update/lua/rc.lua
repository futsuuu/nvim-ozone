local helper = require("test.helper")

local common = require("common") ---@module "test.e2e.update.lua.common"

local LOCK_PATH = vim.fs.joinpath(vim.fn.stdpath("config"), "ozone-lock.json")
local STAGE_PATH = vim.fs.joinpath(vim.fn.stdpath("state"), "update-stage.json")
local REMOVE_REMOVED_FLAG_PATH = common.REMOVE_REMOVED_FLAG_PATH

---@class test.e2e.update.Stage
---@field tracked_next_rev string

---@class test.e2e.update.LockPlugin
---@field url string
---@field version? string
---@field revision? string

---@class test.e2e.update.LockFile
---@field plugins table<string, test.e2e.update.LockPlugin>

---@param path string
---@param value string
---@return nil
local function write_text(path, value)
    local dir_path = assert(vim.fs.dirname(path))
    assert(1 == vim.fn.mkdir(dir_path, "p"))
    local file = assert(io.open(path, "w"))
    assert(file:write(value))
    assert(file:close())
end

---@param path string
---@return string
local function read_text(path)
    local file = assert(io.open(path, "r"))
    local data = assert(file:read("*a"))
    assert(file:close())
    return data
end

---@return test.e2e.update.LockFile
local function read_lock_file()
    local decoded = assert(common.read_json(LOCK_PATH)) --[[@as test.e2e.update.LockFile]]
    return decoded --[[@as test.e2e.update.LockFile]]
end

local meta = assert(common.read_json(common.META_PATH)) --[[@as test.e2e.update.Meta]]
local stage = common.read_json(STAGE_PATH) --[[@as test.e2e.update.Stage?]]

if stage == nil then
    assert(vim.g.update_tracked_value == "v1")
    assert(vim.g.update_versioned_value == "v1")
    assert(vim.g.update_removed_value == "present")

    local lock_before_update = read_lock_file()
    assert(lock_before_update.plugins.tracked.revision == meta.tracked_rev)
    assert(lock_before_update.plugins.versioned.revision == meta.versioned_rev)
    assert(lock_before_update.plugins.removed ~= nil)

    local tracked_next_rev = helper.git_commit(meta.tracked_repo, {
        ["plugin/tracked.lua"] = [[
vim.g.update_tracked_value = "v2"
]],
    })

    local stage_data = {
        tracked_next_rev = tracked_next_rev,
    }
    common.write_json(STAGE_PATH, stage_data)
    write_text(REMOVE_REMOVED_FLAG_PATH, "1")

    require("ozone").update()

    local lock_after_update = read_lock_file()
    assert(lock_after_update.plugins.tracked.revision == tracked_next_rev)
    assert(lock_after_update.plugins.versioned.revision == meta.versioned_rev)
    assert(lock_after_update.plugins.removed ~= nil)

    local tracked_plugin_file =
        vim.fs.joinpath(vim.fn.stdpath("data"), "ozone", "_", "tracked", "plugin", "tracked.lua")
    local tracked_plugin_source = read_text(tracked_plugin_file)
    assert(string.find(tracked_plugin_source, [["v1"]], 1, true) ~= nil)
else
    require("ozone").run()

    assert(vim.g.update_tracked_value == "v2")
    assert(vim.g.update_versioned_value == "v1")

    local lock_after_run = read_lock_file()
    assert(lock_after_run.plugins.tracked.revision == stage.tracked_next_rev)
    assert(lock_after_run.plugins.versioned.revision == meta.versioned_rev)
    assert(lock_after_run.plugins.removed == nil)
end
