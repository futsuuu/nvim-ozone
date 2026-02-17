local Queue = require("ozone.x.queue")
local coro = require("ozone.x.coro")
local uv = require("ozone.x.uv")

local M = {}

---@param path string
---@return string? data, string? err
function M.read_file(path)
    local fd, err_open = uv.fs_open(path, "r", 438) -- 0o666
    if not fd then
        return nil, err_open
    end
    local stat, err_stat = uv.fs_fstat(fd)
    if not stat then
        uv.fs_close(fd)
        return nil, err_stat
    end

    local data, err_read = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)
    if err_read then
        return nil, err_read
    end

    return data, nil
end

---@param path string
---@param data string
---@param mode integer?
---@return boolean? success, string? err
function M.write_file(path, data, mode)
    mode = mode or 438 -- 0o666
    local fd, err_open = uv.fs_open(path, "w", mode)
    if not fd then
        return nil, err_open
    end

    local _, err_write = uv.fs_write(fd, data, 0)
    uv.fs_close(fd)
    if err_write then
        return nil, err_write
    end

    return true, nil
end

---@param path string
---@param mode integer?
---@return boolean? success, string? err
function M.create_dir(path, mode)
    mode = mode or 511 -- 0o777
    return uv.fs_mkdir(path, mode)
end

---@param path string
---@param mode integer?
---@return boolean? success, string? err
function M.create_dir_all(path, mode)
    mode = mode or 511 -- 0o777
    local normalized_path = vim.fs.normalize(path)
    if M.is_dir(normalized_path) then
        return true
    end
    local parent = vim.fs.dirname(normalized_path)
    if parent and parent ~= normalized_path then
        local success, err = M.create_dir_all(parent, mode)
        if not success then
            return nil, err
        end
    end
    local success, err = M.create_dir(normalized_path, mode)
    if success or M.is_dir(normalized_path) then
        return true, nil
    end
    return nil, err
end

---@param path string
---@return boolean? success, string? err
function M.remove_dir(path)
    return uv.fs_rmdir(path)
end

---@param path string
---@return boolean? success, string? err
function M.remove_file(path)
    return uv.fs_unlink(path)
end

---@param path string
---@return boolean? success, string? err
function M.remove_dir_all(path)
    local entries, read_dir_err = M.read_dir(path)
    if not entries then
        return nil, read_dir_err
    end
    local queue = Queue.Counting.new()
    -- spawn coroutines for each entry in the directory
    for i, entry in entries:iter() do
        if not i then
            return nil, entry -- entry is the error message in this case
        end
        local entry_path = vim.fs.joinpath(path, entry.name)
        if entry.type == "directory" then
            coro.pspawn(queue:callback(), M.remove_dir_all, entry_path)
        else
            coro.pspawn(queue:callback(), M.remove_file, entry_path)
        end
    end
    while not queue:is_completed() do
        local _, success, err = assert(queue:get())
        if not success then
            return nil, err
        end
    end
    return M.remove_dir(path)
end

---@class ozone.x.fs.ReadDir
---@field private _handle luv_dir_t
---@field private _entries { name: string, type: string }[]
---@field private _base_index integer
local ReadDir = {}
---@private
ReadDir.__index = ReadDir

--- ```lua
--- for i, entry in assert(fs.read_dir("/path/to/dir")):iter() do
---     if i then
---         print(entry.name .. ": " .. entry.type)
---     else
---         print("error: " .. entry)
---         break
---     end
--- end
--- ```
---@param path string
---@param chunk_size integer? Number of entries read at once.
---@return ozone.x.fs.ReadDir?
---@return string? error
function M.read_dir(path, chunk_size)
    local dir, err = uv.fs_opendir(path, chunk_size)
    if not dir then
        return nil, err
    end
    local self = setmetatable({
        _handle = dir,
        _entries = {},
        _base_index = 0,
    }, ReadDir --[[@as ozone.x.fs.ReadDir]])
    return self, nil
end

---@return async fun(self: self, current_index: false | integer?): index: false | integer?, entry: any | { name: string, type: string }?
---@return self
function ReadDir:iter()
    return self.next, self
end

---@param current_index false | integer?
---@return false | integer? index
---@return string | { name: string, type: string }? entry
function ReadDir:next(current_index)
    if current_index == nil then
        current_index = 0
    end
    if current_index then
        local next_item = self._entries[current_index + 1 - self._base_index]
        if next_item then
            return current_index + 1, next_item
        end
    end
    local entries, err = uv.fs_readdir(self._handle)
    if current_index then
        -- save current index before returning `false`
        self._base_index = current_index
    end
    if err then
        return false, err
    end
    if not entries or not entries[1] then
        uv.fs_closedir(self._handle)
        return nil
    end
    self._entries = entries
    return self._base_index + 1, self._entries[1]
end

---@param path string
---@return boolean? exists
function M.exists(path)
    local stat, err = uv.fs_stat(path)
    return not err and stat ~= nil
end

---@param path string
---@return boolean? is_dir
function M.is_dir(path)
    local stat = uv.fs_stat(path)
    if not stat then
        return false
    end
    return stat.type == "directory"
end

---@param path string
---@return boolean? is_file
function M.is_file(path)
    local stat = uv.fs_stat(path)
    if not stat then
        return false
    end
    return stat.type == "file"
end

---@return string
function M.temp_name()
    return vim.fs.basename(os.tmpname())
end

return M
