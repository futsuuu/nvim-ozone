local uv = vim.uv

local coro = require("ozone.x.coro")

local M = {}

---@generic A, T
---@param resume fun(res: T?, err: string?)
---@param fn fun(a: A, cb: fun(err: string?, res: T?))
---@param a A
---@return nil
local function f1(resume, fn, a)
    fn(a, resume)
end

---@generic A, B, T
---@param resume fun(res: T?, err: string?)
---@param fn fun(a: A, b: B, cb: fun(err: string?, res: T?))
---@param a A
---@param b B
---@return nil
local function f2(resume, fn, a, b)
    fn(a, b, resume)
end

---@generic A, B, C, T
---@param resume fun(res: T?, err: string?)
---@param fn fun(a: A, b: B, c: C, cb: fun(err: string?, res: T?))
---@param a A
---@param b B
---@param c C
---@return nil
local function f3(resume, fn, a, b, c)
    fn(a, b, c, resume)
end

---@generic A, B
---@param a A
---@param b B
---@return B, A
local function reverse(a, b)
    return b, a
end

---@param fd integer
---@return boolean? success, string? err
function M.fs_close(fd)
    return reverse(coro.await(f1, uv.fs_close, fd))
end

---@param dir luv_dir_t
---@return boolean? success, string? err
function M.fs_closedir(dir)
    return reverse(coro.await(f1, uv.fs_closedir, dir))
end

---@param path string
---@param new_path string
---@param flags uv.aliases.fs_copyfile_flags?
---@return boolean? success, string? err
function M.fs_copyfile(path, new_path, flags)
    return reverse(coro.await(f3, uv.fs_copyfile, path, new_path, flags))
end

---@param fd integer
---@return uv.aliases.fs_stat_table? stat, string? err
function M.fs_fstat(fd)
    return reverse(coro.await(f1, uv.fs_fstat, fd))
end

---@param path string
---@param new_path string
---@return boolean? success, string? err
function M.fs_link(path, new_path)
    return reverse(coro.await(f2, uv.fs_link, path, new_path))
end

---@param path string
---@param new_path string
---@param flags uv.aliases.fs_symlink_flags | integer
---@return boolean? success, string? err
function M.fs_symlink(path, new_path, flags)
    return reverse(coro.await(f3, uv.fs_symlink, path, new_path, flags))
end

---@param path string
---@param mode integer
---@return boolean? success, string? err
function M.fs_mkdir(path, mode)
    return reverse(coro.await(f2, uv.fs_mkdir, path, mode))
end

---@param path string
---@param flags uv.aliases.fs_access_flags | integer
---@param mode integer
---@return integer? fd, string? err
function M.fs_open(path, flags, mode)
    return reverse(coro.await(f3, uv.fs_open, path, flags, mode))
end

do
    ---@param resume fun(err: string?, dir: luv_dir_t?)
    ---@param path string
    ---@param entries integer?
    ---@return nil
    local function f(resume, path, entries)
        ---@diagnostic disable-next-line: param-type-mismatch
        uv.fs_opendir(path, resume, entries)
    end

    ---@param path string
    ---@param entries integer?
    ---@return luv_dir_t? dir, string? err
    function M.fs_opendir(path, entries)
        return reverse(coro.await(f, path, entries))
    end
end

---@param fd integer
---@param size integer
---@param offset integer?
---@return string? data, string? err
function M.fs_read(fd, size, offset)
    return reverse(coro.await(f3, uv.fs_read, fd, size, offset))
end

---@param dir luv_dir_t
---@return uv.aliases.fs_readdir_entries? entries, string? err
function M.fs_readdir(dir)
    return reverse(coro.await(f1, uv.fs_readdir, dir))
end

---@param path string
---@return string? path, string? err
function M.fs_realpath(path)
    return reverse(coro.await(f1, uv.fs_realpath, path))
end

---@param path string
---@param new_path string
---@return boolean? success, string? err
function M.fs_rename(path, new_path)
    return reverse(coro.await(f2, uv.fs_rename, path, new_path))
end

---@param path string
---@return uv.aliases.fs_stat_table? success, string? err
function M.fs_stat(path)
    return reverse(coro.await(f1, uv.fs_stat, path))
end

---@param fd integer
---@param data uv.aliases.buffer
---@param offset integer?
---@return integer? bytes_written, string? err
function M.fs_write(fd, data, offset)
    return reverse(coro.await(f3, uv.fs_write, fd, data, offset))
end

---@param path string
---@return boolean? success, string? err
function M.fs_rmdir(path)
    return reverse(coro.await(f1, uv.fs_rmdir, path))
end

---@param path string
---@return boolean? success, string? err
function M.fs_unlink(path)
    return reverse(coro.await(f1, uv.fs_unlink, path))
end

return M
