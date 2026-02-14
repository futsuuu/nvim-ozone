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

runner.add("traceback() indicates coroutine boundaries and statuses", function()
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

runner.add("traceback() indicates unmanaged coroutine", function()
    local co = coroutine.create(function()
        return coro.traceback("hello")
    end)
    local _, traceback = assert(coroutine.resume(co))
    local expected = [[
hello
stack traceback:
    ^-- running (unmanaged)
    ...]]
    expected = expected:gsub("    ", "\t")
    assert(traceback == expected)
end)

---@param ... any
---@return table
local function pack(...)
    return { n = select("#", ...), ... }
end

runner.add("xpspawn() doesn't execute callback immediately", function()
    local body = false
    local callback = false
    coro.xpspawn(function()
        callback = true
    end, function()
        body = true
    end, function(msg)
        return msg
    end)
    assert(body)
    assert(not callback)
end)

runner.add("xpspawn() passes results to callback", function()
    local result = pack(coro.await(coro.xpspawn, function(...)
        coro.await(vim.schedule)
        return ...
    end, function(message)
        return message
    end, nil, "a", nil, "b"))
    assert(result.n == 5)
    assert(result[1] == true)
    assert(result[2] == nil)
    assert(result[3] == "a")
    assert(result[4] == nil)
    assert(result[5] == "b")
end)

runner.add("xpspawn() starts a new coroutine with the given message handler", function()
    local err = {}
    local result = pack(coro.await(coro.xpspawn, function()
        coro.await(vim.schedule)
        return error(err)
    end, function(message)
        assert(message == err)
        return debug.getinfo(2, "f").func
    end))
    assert(result.n == 2)
    assert(result[1] == false)
    assert(result[2] == error, "message handler must not be wrapped without a tail call")
end)

runner.add("pspawn() doesn't execute callback immediately", function()
    local body = false
    local callback = false
    coro.pspawn(function()
        callback = true
    end, function()
        body = true
    end)
    assert(body)
    assert(not callback)
end)

runner.add("pspawn() passes through raw errors", function()
    local err = {}
    local result = pack(coro.await(coro.pspawn, function()
        coro.await(vim.schedule)
        error(err)
    end))
    assert(result.n == 2)
    assert(result[1] == false)
    assert(result[2] == err)
end)
