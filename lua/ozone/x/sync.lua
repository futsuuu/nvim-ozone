-- Synchronization utilities for use in asynchronous contexts.
local sync = {}

local coro = require("ozone.x.coro")

---@class ozone.x.sync.Group
---@field private _count integer
---@field private _resume? fun()
local Group = {}
sync.Group = Group
---@private
Group.__index = Group

---@return self
function Group.new()
    return setmetatable({
        _count = 0,
    }, Group)
end

---@param n integer
function Group:add(n)
    assert(self._resume == nil)
    self._count = self._count + n
end

function Group:done()
    assert(0 < self._count)
    self._count = self._count - 1
    if self._resume and self._count == 0 then
        self._resume()
    end
end

function Group:wait()
    coro.await(function(resume)
        if self._count == 0 then
            resume()
        else
            self._resume = resume
        end
    end)
end

---@param fn async fun(...: any)
---@param ... any
---@return thread
function Group:spawn(fn, ...)
    return coro.spawn(function(...)
        self:add(1)
        fn(...)
        self:done()
    end, ...)
end

return sync
