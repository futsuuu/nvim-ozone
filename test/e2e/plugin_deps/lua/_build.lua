local ozone = require("ozone")

local helper = require("test.helper")

local base_path = helper.temp_dir({
    ["plugin/base.lua"] = [[
vim.g.plugin_dep_order = (vim.g.plugin_dep_order or "") .. "base>"
]],
})

local middle_path = helper.temp_dir({
    ["plugin/middle.lua"] = [[
vim.g.plugin_dep_order = (vim.g.plugin_dep_order or "") .. "middle>"
]],
})

local top_path = helper.temp_dir({
    ["plugin/top.lua"] = [[
vim.g.plugin_dep_order = (vim.g.plugin_dep_order or "") .. "top>"
]],
})

ozone.add({
    top = {
        path = top_path,
        deps = { "middle" },
    },
    base = {
        path = base_path,
    },
    middle = {
        path = middle_path,
        deps = { "base" },
    },
})
