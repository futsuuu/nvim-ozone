local runner = require("test.runner")

local Config = require("ozone.config")
local Lock = require("ozone.lock")

---@param values string[]
---@param expected string
---@return boolean
local function includes(values, expected)
    for _, value in ipairs(values) do
        if value == expected then
            return true
        end
    end
    return false
end

runner.add("add_plugin() resolves local path specs", function()
    local config = Config.new()
    local raw_path = vim.fn.stdpath("cache") .. "/plugins/example/../example"

    local resolved = config:add_plugin("local_plugin", {
        path = raw_path,
    })

    assert(resolved.name == "local_plugin")
    assert(resolved.path == vim.fs.normalize(raw_path))
    assert(resolved.source.kind == "path")
end)

runner.add("add_plugin() resolves git specs with default install path", function()
    local config = Config.new()

    local resolved = config:add_plugin("remote_plugin", {
        url = "https://github.com/author/repo",
        version = "v1.2.3",
    })

    assert(resolved.name == "remote_plugin")
    assert(resolved.path == vim.fs.joinpath(vim.fn.stdpath("data"), "ozone", "_", "remote_plugin"))
    assert(resolved.source.kind == "git")
    assert(resolved.source.url == "https://github.com/author/repo")
    assert(resolved.source.version == "v1.2.3")
    assert(resolved.source.revision == nil)
end)

runner.add("add_plugin() rejects duplicate plugin names", function()
    local config = Config.new()
    config:add_plugin("dup_plugin", {
        path = vim.fn.stdpath("cache") .. "/plugins/dup_plugin",
    })

    local ok, err = pcall(config.add_plugin, config, "dup_plugin", {
        path = vim.fn.stdpath("cache") .. "/plugins/dup_plugin_2",
    })
    assert(ok == false)
    assert(type(err) == "string")
    assert(string.match(err, 'plugin name "dup_plugin" is duplicated %(definition #2%)') ~= nil)
end)

runner.add("add_plugin() validates version source requirements", function()
    local config = Config.new()
    local ok, err = pcall(config.add_plugin, config, "version_without_url", {
        path = vim.fn.stdpath("cache") .. "/plugins/version_without_url",
        version = "main",
    })
    assert(ok == false)
    assert(type(err) == "string")
    assert(string.match(err, "'version_without_url.version' requires 'version_without_url.url'") ~= nil)
end)

runner.add("add_plugin() applies locked revision from lock file data", function()
    local config = Config.new()
    local lock = Lock.default()
    lock.plugins.revision_plugin = {
        url = "https://github.com/author/repo",
        version = "v1.2.3",
        revision = "0123456789abcdef",
    }
    config:set_lock(lock)

    local resolved = config:add_plugin("revision_plugin", {
        url = "https://github.com/author/repo",
        version = "v1.2.3",
    })

    assert(resolved.name == "revision_plugin")
    assert(resolved.path == vim.fs.joinpath(vim.fn.stdpath("data"), "ozone", "_", "revision_plugin"))
    assert(resolved.source.kind == "git")
    assert(resolved.source.url == "https://github.com/author/repo")
    assert(resolved.source.version == "v1.2.3")
    assert(resolved.source.revision == "0123456789abcdef")
end)

runner.add("add_plugin() requires path or url", function()
    local config = Config.new()
    local ok, err = pcall(config.add_plugin, config, "missing_source", {})
    assert(ok == false)
    assert(type(err) == "string")
    assert(string.match(err, "'missing_source.path' or 'missing_source.url' must be set") ~= nil)
end)

runner.add("add_plugin() validates plugin names", function()
    local config = Config.new()
    local ok, err = pcall(config.add_plugin, config, "invalid/name", {
        path = vim.fn.stdpath("cache") .. "/plugins/invalid_name",
    })
    assert(ok == false)
    assert(type(err) == "string")
    assert(string.match(err, "plugin name") ~= nil)
end)

runner.add("add_plugin() validates deps", function()
    local config = Config.new()
    local invalid_deps_spec = {
        path = vim.fn.stdpath("cache") .. "/plugins/invalid_deps",
        deps = "foo",
    }

    local ok, err = pcall(config.add_plugin, config, "invalid_deps", invalid_deps_spec)
    assert(ok == false)
    assert(type(err) == "string")
    assert(string.match(err, "invalid type of 'invalid_deps.deps'") ~= nil)

    ok, err = pcall(config.add_plugin, config, "invalid_dep_name", {
        path = vim.fn.stdpath("cache") .. "/plugins/invalid_dep_name",
        deps = { "bad/name" },
    })
    assert(ok == false)
    assert(type(err) == "string")
    assert(string.match(err, "invalid_dep_name.deps%[1%]") ~= nil)
end)

runner.add("get_plugin_names_in_load_order() orders plugins by deps", function()
    local config = Config.new()

    local base = config:add_plugin("base", {
        path = vim.fn.stdpath("cache") .. "/plugins/base",
    })
    local middle = config:add_plugin("middle", {
        path = vim.fn.stdpath("cache") .. "/plugins/middle",
        deps = { "base" },
    })
    local top = config:add_plugin("top", {
        path = vim.fn.stdpath("cache") .. "/plugins/top",
        deps = { "middle", "base" },
    })

    local order, warnings = config:get_plugin_names_in_load_order()
    assert(#warnings == 0)
    assert(#order == 3)
    assert(order[1] == "base")
    assert(order[2] == "middle")
    assert(order[3] == "top")
    assert(#middle.deps == 1)
    assert(middle.deps[1] == base)
    assert(#top.deps == 2)
    assert(top.deps[1] == base)
    assert(top.deps[2] == middle)
end)

runner.add("get_plugin_names_in_load_order() warns on undefined deps", function()
    local config = Config.new()
    local plugin = config:add_plugin("missing_dep_plugin", {
        path = vim.fn.stdpath("cache") .. "/plugins/missing_dep_plugin",
        deps = { "unknown" },
    })

    local order, warnings = config:get_plugin_names_in_load_order()
    assert(#warnings == 1)
    assert(string.match(warnings[1], 'plugin "missing_dep_plugin" depends on undefined plugin "unknown"') ~= nil)
    assert(#order == 1)
    assert(order[1] == "missing_dep_plugin")
    assert(#plugin.deps == 0)
end)

runner.add("get_plugin_names_in_load_order() warns on circular deps", function()
    local config = Config.new()
    config:add_plugin("a", {
        path = vim.fn.stdpath("cache") .. "/plugins/cycle_a",
        deps = { "b" },
    })
    config:add_plugin("b", {
        path = vim.fn.stdpath("cache") .. "/plugins/cycle_b",
        deps = { "a" },
    })

    local order, warnings = config:get_plugin_names_in_load_order()
    assert(#warnings == 1)
    assert(string.match(warnings[1], "circular dependency") ~= nil)
    assert(#order == 2)
    assert(includes(order, "a"))
    assert(includes(order, "b"))
end)
