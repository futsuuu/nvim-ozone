local runner = require("test.runner")

local coro = require("ozone.x.coro")

runner.add("await() handles varargs correctly", function()
    assert(0 == select(
        "#",
        coro.await(function(resume)
            resume()
        end)
    ))
    assert(4 == select(
        "#",
        coro.await(function(resume)
            resume(nil, nil, nil, nil)
        end)
    ))
end)
