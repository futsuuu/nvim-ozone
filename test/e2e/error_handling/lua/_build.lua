local ozone = require("ozone")

local helper = require("test.helper")

local ok_repo = helper.git_repo({
    ["plugin/ok.lua"] = [[
vim.g.error_handling_ok_count = (vim.g.error_handling_ok_count or 0) + 1
]],
})

local duplicate_path = helper.temp_dir({
    ["plugin/duplicate.lua"] = [[
vim.g.error_handling_duplicate_count = (vim.g.error_handling_duplicate_count or 0) + 1
]],
})

local invalid_name_path = helper.temp_dir({
    ["plugin/invalid_name.lua"] = [[
vim.g.error_handling_invalid_name_count = (vim.g.error_handling_invalid_name_count or 0) + 1
]],
})

ozone.add({
    ---@diagnostic disable-next-line: assign-type-mismatch
    invalid_spec = "not-a-table",
    missing_source = {},
    version_without_url = {
        version = "v1.0.0",
    },
    invalid_url_type = {
        ---@diagnostic disable-next-line: assign-type-mismatch
        url = {},
    },
    clone_failure = {
        url = vim.fs.joinpath(vim.fn.stdpath("cache"), "missing", "repository"),
    },
    duplicate = {
        path = duplicate_path,
    },
    ["invalid/name"] = {
        path = invalid_name_path,
    },
    ok = {
        url = ok_repo,
    },
})

ozone.add({
    duplicate = {
        path = duplicate_path,
    },
})
