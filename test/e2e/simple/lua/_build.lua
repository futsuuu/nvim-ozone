local ozone = require("ozone")

local helper = require("test.helper")

ozone.add({
    foo = {
        path = helper.temp_dir({
            ["plugin/foo.lua"] = [[
vim.g.foo_count = (vim.g.foo_count or 0) + 1
]],
        }),
    },
})
