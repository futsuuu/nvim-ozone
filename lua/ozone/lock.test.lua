local runner = require("test.runner")

local Config = require("ozone.config")
local fs = require("ozone.x.fs")
local lock = require("ozone.lock")

---@param specs table<string, ozone.PluginSpec>
---@return ozone.Config
local function lock_config_from_specs(specs)
    local config = Config.new()
    for name, spec in pairs(specs) do
        config:add_plugin(name, spec)
    end
    return config
end

runner.add("write() formats lock file deterministically", function()
    local path = lock.path()
    local original = nil ---@type string?
    if fs.exists(path) then
        original = assert(fs.read_file(path))
    end

    local ok, err = pcall(function()
        assert(lock.write(lock_config_from_specs({
            zebra = {
                url = "https://example.com/zebra",
                version = "v1.0.0",
                revision = "rev-z",
            },
            alpha = {
                url = "https://example.com/alpha",
                revision = "rev-a",
            },
        })))
        local first = assert(fs.read_file(path))

        assert(lock.write(lock_config_from_specs({
            alpha = {
                url = "https://example.com/alpha",
                revision = "rev-a",
            },
            zebra = {
                url = "https://example.com/zebra",
                version = "v1.0.0",
                revision = "rev-z",
            },
        })))
        local second = assert(fs.read_file(path))

        local expected = [[
{
  "plugins": {
    "alpha": {
      "url": "https://example.com/alpha",
      "revision": "rev-a"
    },
    "zebra": {
      "url": "https://example.com/zebra",
      "version": "v1.0.0",
      "revision": "rev-z"
    }
  }
}
]]
        assert(first == expected)
        assert(second == expected)
    end)

    if original == nil then
        if fs.exists(path) then
            assert(fs.remove_file(path))
        end
    else
        assert(fs.write_file(path, original))
    end

    assert(ok, err)
end)

runner.add("read() treats JSON null version as absent", function()
    local path = lock.path()
    local original = nil ---@type string?
    if fs.exists(path) then
        original = assert(fs.read_file(path))
    end

    local ok, err = pcall(function()
        local before = [[
{
  "plugins": {
    "tracked": {
      "url": "https://example.com/tracked",
      "version": null,
      "revision": "rev-1"
    }
  }
}
]]
        assert(fs.write_file(path, before))

        local lock_config = lock.read()
        local plugins = lock_config:get_plugins()
        assert(plugins.tracked.source.kind == "git")
        assert(plugins.tracked.source.version == nil)
        assert(plugins.tracked.source.revision == "rev-1")

        assert(lock.write(lock_config))
        local after = assert(fs.read_file(path))
        local expected = [[
{
  "plugins": {
    "tracked": {
      "url": "https://example.com/tracked",
      "revision": "rev-1"
    }
  }
}
]]
        assert(after == expected)
    end)

    if original == nil then
        if fs.exists(path) then
            assert(fs.remove_file(path))
        end
    else
        assert(fs.write_file(path, original))
    end

    assert(ok, err)
end)
