local runner = require("test.runner")

local Config = require("ozone.config")

runner.add("add_plugin() resolves local path specs", function()
    local config = Config.new()
    local raw_path = vim.fn.stdpath("cache") .. "/plugins/example/../example"

    local resolved = config:add_plugin("local_plugin", {
        path = raw_path,
    })

    assert(resolved.path == vim.fs.normalize(raw_path))
    assert(resolved.source.kind == "path")
end)

runner.add("add_plugin() resolves git specs with default install path", function()
    local config = Config.new()

    local resolved = config:add_plugin("remote_plugin", {
        url = "https://github.com/author/repo",
        version = "v1.2.3",
    })

    assert(resolved.path == vim.fs.joinpath(vim.fn.stdpath("data"), "ozone", "_", "remote_plugin"))
    assert(resolved.source.kind == "git")
    assert(resolved.source.url == "https://github.com/author/repo")
    assert(resolved.source.version == "v1.2.3")
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
    assert(
        string.match(err, "'version_without_url.version' requires 'version_without_url.url'") ~= nil
    )
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
