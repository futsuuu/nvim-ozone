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

runner.add("traceback() works like debug.traceback()", function()
    assert(string.match(coro.traceback(), "^stack traceback:"))
    assert(string.match(coro.traceback(), ": in main chunk$"))
    assert(string.match(coro.traceback(1), "^1\nstack traceback:"))
    assert(string.match(coro.traceback("hello"), "^hello\nstack traceback:"))
    local tbl = {}
    assert(tbl == coro.traceback(tbl))
    assert(nil == coro.traceback(nil))
    assert(false == coro.traceback(false))
    coro.await(function(resume)
        vim.schedule(function()
            assert(coroutine.running() == nil)
            assert(coro.traceback() == debug.traceback())
            assert(coro.traceback("hello") == debug.traceback("hello"))
            resume()
        end)
    end)
end)

runner.add("traceback() shows coroutine boundaries and statuses", function()
    local traceback = coro.await(function(resume)
        coro.spawn(function()
            coro.spawn(function()
                (function()
                    coro.spawn(function()
                        coro.await(vim.schedule)
                        resume(coro.traceback("hello"))
                    end)
                    coro.await(vim.schedule)
                end)()
            end)
        end)
    end)
    local short_src = debug.getinfo(1, "S").short_src
    local pattern = [[
^hello
stack traceback:
    short_src:%d+: in function <short_src:%d+>
    %^%-%- running
    short_src:%d+: in function <short_src:%d+>
    short_src:%d+: in function <short_src:%d+>
    %^%-%- suspended
    short_src:%d+: in function <short_src:%d+>
    %^%-%- dead
    ...]]
    pattern = pattern:gsub("short_src", vim.pesc(short_src))
    pattern = pattern:gsub("    ", "\t")
    assert(string.match(traceback, pattern))
end)
