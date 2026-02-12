---@type string
local modname = ...

local coro = {}

--- TODO: make to work with unmanaged coroutines

---@class ozone.x.coro.Context
---@field parent? thread
---@field traceback string
---@type table<thread, ozone.x.coro.Context>
local managed = setmetatable({}, { __mode = "k" })

function coro.current()
    local co = coroutine.running()
    if not co then
        return nil, "currently running in the main thread"
    end
    if not managed[co] then
        return nil, ("%s is not managed by %q"):format(co, modname)
    end
    return co
end

--- A wrapper of `debug.traceback()`.
---
--- NOTE: this is only intended to be used for debugging purpose.
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
    local cx = co and managed[co] ---@type ozone.x.coro.Context?
    while co and cx do
        traceback = ("%s\n\t^-- %s%s"):format(traceback, coroutine.status(co), cx.traceback)
        co = cx.parent
        cx = co and managed[co]
    end
    traceback = traceback:gsub("\n\t%[builtin#21%]: at 0x%x+", "") -- remove `xpcall`
    return traceback
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
    if xpcall_success then
        return ...
    end
    local err = ...
    error(type(err) == "string" and setmetatable({}, {
        __tostring = function()
            return err
        end,
    }) or err)
end

---@param fn async fun(...)
---@param ... any
function coro.spawn(fn, ...)
    local co = coroutine.create(xpcall)
    managed[co] = {
        parent = coro.current(),
        traceback = debug.traceback("", 2):sub(#"\nstack traceback:" + 1),
    }
    handle_resume_result_of_xpcall(co, coroutine.resume(co, fn, coro.traceback, ...))
    return co
end

---@param fn fun(resume: fun(...: any), ...: any)
---@param ... any additional arguments for `fn`
---@return any ... arguments passed to `resume`
function coro.await(fn, ...)
    local co = assert(coro.current())
    local has_resumed = false
    local function resume(...)
        if has_resumed then
            return
        end
        has_resumed = true
        local result = { [0] = select("#", ...), ... }
        return vim.schedule(function()
            handle_resume_result_of_xpcall(co, coroutine.resume(co, unpack(result, 1, result[0])))
        end)
    end
    fn(resume, ...)
    return coroutine.yield()
end

do
    ---@param ... any
    ---@return table
    local function pack(...)
        return { [0] = select("#", ...), ... }
    end

    ---@param fn async fun(...: any): ...: any
    ---@param ... any
    ---@return any ...
    function coro.wait(fn, ...)
        local result = nil ---@type table?
        local co = coro.spawn(function(...)
            result = pack(fn(...))
        end, ...)
        vim.wait(2 ^ 20, function()
            return coroutine.status(co) == "dead"
        end)
        assert(result)
        return unpack(result, 1, result[0])
    end
end

return coro
