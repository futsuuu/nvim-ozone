---@type string
local modname = ...

local coro = {}

--- TODO: make to work with unmanaged coroutines

---@class ozone.x.coro.State
---@field parent? thread
---@field traceback string
---@type table<thread, ozone.x.coro.State>
local state_map = setmetatable({}, { __mode = "k" })

function coro.current()
    local co = coroutine.running()
    if not co then
        return nil, "currently running in the main thread"
    end
    if not state_map[co] then
        return nil, ("%s is not managed by %q"):format(co, modname)
    end
    return co
end

---@type fun(co: thread, ...: any): ...: any
local resume_coroutine
do
    ---@param co thread
    ---@param resume_success boolean
    ---@param second any
    ---@param ... any
    ---@return any ...
    local function handle_result(co, resume_success, second, ...)
        assert(resume_success)
        if coroutine.status(co) ~= "dead" then
            return second, ...
        end
        local xpcall_success = second ---@type boolean
        if xpcall_success then
            return ...
        end
        local err = ...
        if type(err) ~= "string" then
            error(err)
        end
        ---@cast err string
        local state = state_map[co] ---@type ozone.x.coro.State?
        while state do
            err = err .. state.traceback
            state = state.parent and state_map[state.parent]
        end
        -- TODO: reimplement `debug.traceback()`
        err = err:gsub("\n\t%[builtin#21%]: at 0x%x+", "") -- remove `xpcall`
        error(setmetatable({}, {
            __tostring = function()
                return err
            end,
        }))
    end
    function resume_coroutine(co, ...)
        return handle_result(co, coroutine.resume(co, ...))
    end
end

---@param fn async fun(...)
---@param ... any
function coro.spawn(fn, ...)
    local co = coroutine.create(xpcall)
    state_map[co] = {
        parent = coro.current(),
        traceback = debug.traceback("dummy", 2):gsub("^dummy\nstack traceback:", ""),
    }
    resume_coroutine(co, fn, debug.traceback, ...)
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
            resume_coroutine(co, unpack(result, 1, result[0]))
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
