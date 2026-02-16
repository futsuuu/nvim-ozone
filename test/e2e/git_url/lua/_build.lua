local ozone = require("ozone")

local helper = require("test.helper")

local foo_repo = helper.git_repo({
    ["plugin/foo.lua"] = [[
vim.g.foo_git_count = (vim.g.foo_git_count or 0) + 1
]],
})

local bar_repo = helper.git_repo({
    ["plugin/bar.lua"] = [[
vim.g.bar_git_count = (vim.g.bar_git_count or 0) + 1
]],
})

local versioned_repo = helper.git_repo({
    ["plugin/versioned.lua"] = [[
vim.g.versioned_git_count = (vim.g.versioned_git_count or 0) + 1
]],
})
local versioned_rev = helper.git_rev(versioned_repo)
helper.git_commit(versioned_repo, {
    ["plugin/versioned.lua"] = [[
vim.g.versioned_git_count = (vim.g.versioned_git_count or 0) + 100
]],
})

local bar_path = vim.fn.stdpath("data") .. "/ozone/custom/bar"

ozone.add({
    foo = {
        url = foo_repo,
    },
    bar = {
        url = bar_repo,
        path = bar_path,
    },
    versioned = {
        url = versioned_repo,
        version = versioned_rev,
    },
})
