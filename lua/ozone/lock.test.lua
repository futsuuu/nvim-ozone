local runner = require("test.runner")

local Lock = require("ozone.lock")

runner.add("encode() formats lock file deterministically", function()
    local first_lock = Lock.default()
    first_lock.plugins.zebra = {
        url = "https://example.com/zebra",
        version = "v1.0.0",
        revision = "rev-z",
    }
    first_lock.plugins.alpha = {
        url = "https://example.com/alpha",
        revision = "rev-a",
    }

    local second_lock = Lock.default()
    second_lock.plugins.alpha = {
        url = "https://example.com/alpha",
        revision = "rev-a",
    }
    second_lock.plugins.zebra = {
        url = "https://example.com/zebra",
        version = "v1.0.0",
        revision = "rev-z",
    }

    local first = first_lock:encode()
    local second = second_lock:encode()

    local expected = [[
{
  "plugins": {
    "alpha": {
      "url": "https://example.com/alpha",
      "version": null,
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

runner.add("decode() keeps null fields encodable", function()
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

    local decoded = Lock.decode(before)
    assert(decoded.plugins.tracked.version == nil)

    local after = decoded:encode()
    local expected = [[
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
    assert(after == expected)
end)
