local runner = require("test.runner")

local fs = require("ozone.x.fs")
local lock = require("ozone.lock")

runner.add("write() formats lock file deterministically", function()
    local path = lock.path()
    local original = nil ---@type string?
    if fs.exists(path) then
        original = assert(fs.read_file(path))
    end

    local ok, err = pcall(function()
        assert(lock.write({
            zebra = {
                url = "https://example.com/zebra",
                revision = "rev-z",
                locked_version = "v1.0.0",
            },
            alpha = {
                url = "https://example.com/alpha",
                revision = "rev-a",
            },
        }))
        local first = assert(fs.read_file(path))

        assert(lock.write({
            alpha = {
                url = "https://example.com/alpha",
                revision = "rev-a",
            },
            zebra = {
                url = "https://example.com/zebra",
                revision = "rev-z",
                locked_version = "v1.0.0",
            },
        }))
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
      "revision": "rev-z",
      "locked_version": "v1.0.0"
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

runner.add("read() treats JSON null locked_version as absent", function()
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
      "revision": "rev-1"
    }
  }
}
]]
        assert(fs.write_file(path, before))

        local plugins = lock.read()
        assert(plugins.tracked.locked_version == nil)

        assert(lock.write(plugins))
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
