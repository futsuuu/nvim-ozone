local runner = require("test.runner")

local Lockfile = require("ozone.lockfile")

runner.add("encode() formats lock file deterministically", function()
    local first_lockfile = Lockfile.default()
    first_lockfile.plugins.zebra = {
        url = "https://example.com/zebra",
        version = "v1.0.0",
        hash = "hash-z",
    }
    first_lockfile.plugins.alpha = {
        url = "https://example.com/alpha",
        hash = "hash-a",
    }

    local second_lockfile = Lockfile.default()
    second_lockfile.plugins.alpha = {
        url = "https://example.com/alpha",
        hash = "hash-a",
    }
    second_lockfile.plugins.zebra = {
        url = "https://example.com/zebra",
        version = "v1.0.0",
        hash = "hash-z",
    }

    local first = first_lockfile:encode()
    local second = second_lockfile:encode()

    local expected = [[
{
  "plugins": {
    "alpha": {
      "url": "https://example.com/alpha",
      "version": null,
      "hash": "hash-a"
    },
    "zebra": {
      "url": "https://example.com/zebra",
      "version": "v1.0.0",
      "hash": "hash-z"
    }
  }
}
]]

    assert(first == expected)
    assert(second == expected)
end)

runner.add("decode() keeps null fields encodable", function()
    local before = [[
{
  "plugins": {
    "tracked": {
      "url": "https://example.com/tracked",
      "version": null,
      "hash": "hash-1"
    }
  }
}
]]

    local decoded = Lockfile.decode(before)
    assert(decoded.plugins.tracked.version == nil)

    local after = decoded:encode()
    local expected = [[
{
  "plugins": {
    "tracked": {
      "url": "https://example.com/tracked",
      "version": null,
      "hash": "hash-1"
    }
  }
}
]]
    assert(after == expected)
end)
