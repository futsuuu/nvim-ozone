local buffer = require("string.buffer")

local coro = require("ozone.x.coro")

--- Multi-prodcer, single consumer queue with multi-value support.
---@class ozone.x.Queue
--- Same as `Queue:put()`, but the `self` argument is bound to the instance.
--- This is useful for passing as a callback.
---@field public put_fn fun(...: any): nil
---@field package [integer] any
---@field package _first integer
---@field package _last integer
---@field package _chunks string.buffer used as `Queue<u8>`
---@field package _on_put? fun(...: any)
local Queue = {}
---@private
Queue.__index = Queue

---@return self
function Queue.new()
    return Queue:_new()
end

---@protected
---@generic T
---@param self T
---@return T
function Queue:_new()
    local instance = setmetatable({
        _first = 1,
        _last = 0,
        _chunks = buffer.new(),
    }, self)
    function instance.put_fn(...)
        return instance:put(...)
    end
    return instance
end

--- Returns the number of chunks in the queue.
---
--- Note that this is not the number of values in the queue.
---@return integer
function Queue:len()
    return #self._chunks
end

--- Puts values into the queue as a chunk. The number of values in the chunk
--- must be less than 256.
---@param ... any
---@return nil
function Queue:put(...)
    local callback = self._on_put
    if callback then
        self._on_put = nil
        callback(...)
        return
    end
    local chunk_size = select("#", ...)
    assert(chunk_size <= 255, "cannot put more than 255 values in one chunk")
    self._chunks:put(string.char(chunk_size))
    for i = 1, chunk_size do
        self[self._last + i] = select(i, ...)
    end
    self._last = self._last + chunk_size
end

do
    ---@param list any[]
    ---@param first integer
    ---@param last integer
    ---@param ... any
    ---@return any ...
    local function clear_range(list, first, last, ...)
        table.move({}, 1, last - first + 1, first, list)
        return ...
    end

    ---@param list any[]
    ---@param first integer
    ---@param last integer
    ---@return any ...
    local function take_range(list, first, last)
        return clear_range(list, first, last, unpack(list, first, last))
    end

    ---@param callback fun(...: any)
    ---@param queue ozone.x.Queue
    local function set_callback(callback, queue)
        queue._on_put = callback
    end

    --- Gets a chunk of values from the queue. If the queue is empty, awaits
    --- until a chunk is put into the queue.
    ---@return any ...
    function Queue:get()
        if #self._chunks == 0 then
            return coro.await(set_callback, self)
        end
        local chunk_size = string.byte(self._chunks:get(1))
        local chunk_first = self._first
        local chunk_last = chunk_first + chunk_size - 1
        self._first = chunk_last + 1
        return take_range(self, chunk_first, chunk_last)
    end
end

---@class ozone.x.Queue.Counting: ozone.x.Queue
---@field private _pendings integer
---@field private _availables integer
local Counting = setmetatable({}, Queue)
Queue.Counting = Counting

---@private
Counting.__index = Counting

function Counting.new()
    local self = Counting:_new()
    self._pendings = 0
    self._availables = 0
    return self
end

---@return boolean
function Counting:is_completed()
    return self._pendings == 0 and self._availables == 0
end

---@return integer
function Counting:pending_count()
    return self._pendings
end

---@return integer
function Counting:available_count()
    return self._availables
end

---@return fun(...: any): nil
function Counting:callback()
    self._pendings = self._pendings + 1
    return self.put_fn
end

---@private
function Counting:put(...)
    self._pendings = self._pendings - 1
    self._availables = self._availables + 1
    return Queue.put(self, ...)
end

---@return any ...
function Counting:get()
    self._availables = self._availables - 1
    return Queue.get(self)
end

return Queue
