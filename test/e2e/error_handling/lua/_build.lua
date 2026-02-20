local ozone = require("ozone")

local helper = require("test.helper")

local ok_repo = helper.git_repo({
    ["plugin/ok.lua"] = [[
vim.g.error_handling_ok_count = (vim.g.error_handling_ok_count or 0) + 1
]],
})

ozone.add({
    clone_failure = {
        url = vim.fs.joinpath(vim.fn.stdpath("cache"), "missing", "repository"),
    },
    ok = {
        url = ok_repo,
    },
})
