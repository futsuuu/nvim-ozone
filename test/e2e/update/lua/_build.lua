local ozone = require("ozone")

local helper = require("test.helper")

local common = require("common") ---@module "test.e2e.update.lua.common"

---@class test.e2e.update.Meta
---@field tracked_repo string
---@field tracked_rev string
---@field versioned_repo string
---@field versioned_rev string
---@field removed_repo string

---@param cmd string[]
---@return nil
local function run_system(cmd)
    local output = vim.fn.system(cmd)
    assert(vim.v.shell_error == 0, output)
end

---@return test.e2e.update.Meta
local function ensure_meta()
    local meta = common.read_json(common.META_PATH) --[[@as test.e2e.update.Meta?]]
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
    common.write_json(common.META_PATH, meta)
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

if vim.uv.fs_stat(common.REMOVE_REMOVED_FLAG_PATH) == nil then
    specs.removed = {
        url = meta.removed_repo,
    }
end

ozone.add(specs)
