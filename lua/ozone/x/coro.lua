local coro = {}

---@class ozone.x.coro.Context
--- The parent coroutine, or `nil` if the parent is the main thread.
---@field parent? thread
---@field callback fun(success: boolean, ...: any)
---@field transparent_xpcall boolean
---@field traceback string
---@type table<thread, ozone.x.coro.Context>
local managed = setmetatable({}, { __mode = "k" })

--- A wrapper of `debug.traceback()`.
---@overload fun(message: any, level?: integer): message: any
function coro.traceback(...)
    local traceback ---@type any
    if select("#", ...) == 0 then
        traceback = debug.traceback("", 2):sub(#"\n" + 1)
    else
        assert(type(...) ~= "thread", "unimplemented")
        local message, level = ... ---@type any, integer?
        traceback = debug.traceback(message, (level or 1) + 1)
    end
    if type(traceback) ~= "string" then
        return traceback
    end
    local co = coroutine.running()
    while co do
        local cx = managed[co] ---@type ozone.x.coro.Context?
        if cx then
            traceback = ("%s\n\t^-- %s%s"):format(traceback, coroutine.status(co), cx.traceback)
            co = cx.parent
        else
            traceback = ("%s\n\t^-- %s (unmanaged)\n\t..."):format(traceback, coroutine.status(co))
            break
        end
    end
    traceback = traceback:gsub("\n\t%[builtin#21%]: at 0x%x+", "") -- remove `xpcall`
    return traceback
end

---@param fn fun(...: any)
---@param ... any
---@return nil
local function schedule(fn, ...)
    local args = { [0] = select("#", ...), ... }
    return vim.schedule(function()
        fn(unpack(args, 1, args[0]))
    end)
end

---@param co thread
---@param resume_success boolean
---@param ... any
---@return any ...
local function handle_resume_result(co, resume_success, ...)
    if coroutine.status(co) ~= "dead" then
        assert(resume_success)
        return ...
    end
    local cx = managed[co]
    if cx then
        schedule(cx.callback, resume_success, ...)
    end
end

--- Runs `fn` in a managed coroutine and reports the result to `callback`.
---
--- NOTE: The variadic arguments exist so callers can pass values directly without
--- creating a per-call closure in hot loops.
---@param callback fun(success: boolean, ...: any)
---@param fn async fun(...): ...: any
---@param ... any
---@return thread
function coro.pspawn(callback, fn, ...)
    local co = coroutine.create(fn)
    managed[co] = {
        parent = coroutine.running(),
        callback = callback,
        transparent_xpcall = false,
        traceback = debug.traceback("", 2):sub(#"\nstack traceback:" + 1),
    }
    handle_resume_result(co, coroutine.resume(co, ...))
    return co
end

---@param co thread
---@param resume_success boolean
---@param second any
---@param ... any
---@return any ...
local function handle_resume_result_of_xpcall(co, resume_success, second, ...)
    assert(resume_success)
    if coroutine.status(co) ~= "dead" then
        return second, ...
    end
    local xpcall_success = second ---@type boolean
    local cx = managed[co]
    if cx then
        schedule(cx.callback, xpcall_success, ...)
    end
end

--- Runs `fn` with `xpcall` in a managed coroutine and reports the result to
--- `callback`.
---
--- NOTE: The variadic arguments exist so callers can pass values directly without
--- creating a per-call closure in hot loops.
---@param callback fun(success: boolean, ...: any)
---@param fn async fun(...): ...: any
---@param message_handler fun(message: any): any
---@param ... any
---@return thread
function coro.xpspawn(callback, fn, message_handler, ...)
    local co = coroutine.create(xpcall)
    managed[co] = {
        parent = coroutine.running(),
        callback = callback,
        transparent_xpcall = true,
        traceback = debug.traceback("", 2):sub(#"\nstack traceback:" + 1),
    }
    handle_resume_result_of_xpcall(co, coroutine.resume(co, fn, message_handler, ...))
    return co
end

do
    ---@param success boolean
    ---@param ... any
    ---@return nil
    local function default_callback(success, ...)
        if not success then
            local err = ...
            error(type(err) == "string" and setmetatable({}, {
                __tostring = function()
                    return err
                end,
            }) or err)
        end
    end

    --- Runs `fn` in a managed coroutine and raises on failure.
    ---
    --- NOTE: The variadic arguments exist so callers can pass values directly without
    --- creating a per-call closure in hot loops.
    ---@param fn async fun(...): ...: any
    ---@param ... any
    ---@return thread
    function coro.spawn(fn, ...)
        return coro.xpspawn(default_callback, fn, coro.traceback, ...)
    end
end

do
    ---@param co thread
    ---@param ... any
    ---@return nil
    local function resume(co, ...)
        local cx = managed[co]
        if cx and cx.transparent_xpcall then
            handle_resume_result_of_xpcall(co, coroutine.resume(co, ...))
        else
            handle_resume_result(co, coroutine.resume(co, ...))
        end
    end

    --- Suspends the current coroutine until `executor` calls `resume(...)`.
    ---
    --- NOTE: `resume` always resumes the coroutine asynchronously.
    --- NOTE: The variadic arguments exist so callers can pass values directly without
    --- creating a per-call closure in hot loops.
    ---@param executor fun(resume: fun(...: any), ...: any)
    ---@param ... any additional arguments for `executor`
    ---@return any ... arguments passed to `resume`
    function coro.await(executor, ...)
        local co = assert(coroutine.running(), "await() must be called in the coroutine")
        local has_resumed = false
        executor(function(...)
            if not has_resumed then
                has_resumed = true
                return schedule(resume, co, ...)
            end
        end, ...)
        return coroutine.yield()
    end
end

--- Runs `fn` and blocks with `vim.wait()` until it completes.
---@param fn async fun(...: any): ...: any
---@param ... any
---@return any ...
function coro.wait(fn, ...)
    local result = nil ---@type table?
    local co = coro.xpspawn(function(...)
        result = { [0] = select("#", ...), ... }
    end, fn, coro.traceback, ...)
    vim.wait(2 ^ 20, function()
        return result ~= nil
    end)
    assert(result)
    assert(coroutine.status(co) == "dead")
    if not result[1] then
        error(setmetatable({}, {
            __tostring = function()
                return tostring(result[2])
            end,
        }))
    end
    return unpack(result, 2, result[0])
end

return coro
