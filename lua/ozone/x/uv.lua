local uv = vim.uv

local coro = require("ozone.x.coro")

local M = {}

---@generic T
---@param resume fun(val: T, err: string?)
---@return fun(err: string?, val: T)
local function create_callback(resume)
    return function(e, v)
        resume(v, e)
    end
end

---@generic A, T
---@param resume fun(res: T?, err: string?)
---@param fn fun(a: A, cb: fun(err: string?, res: T?))
---@param a A
local function f1(resume, fn, a)
    fn(a, create_callback(resume))
end

---@generic A, B, T
---@param resume fun(res: T?, err: string?)
---@param fn fun(a: A, b: B, cb: fun(err: string?, res: T?))
---@param a A
---@param b B
local function f2(resume, fn, a, b)
    fn(a, b, create_callback(resume))
end

---@generic A, B, C, T
---@param resume fun(res: T?, err: string?)
---@param fn fun(a: A, b: B, c: C, cb: fun(err: string?, res: T?))
---@param a A
---@param b B
---@param c C
local function f3(resume, fn, a, b, c)
    fn(a, b, c, create_callback(resume))
end

---@param fd integer
---@return boolean? success, string? err
function M.fs_close(fd)
    return coro.await(f1, uv.fs_close, fd)
end

---@param dir luv_dir_t
---@return boolean? success, string? err
function M.fs_closedir(dir)
    return coro.await(f1, uv.fs_closedir, dir)
end

---@param path string
---@param new_path string
---@param flags uv.aliases.fs_copyfile_flags?
---@return boolean? success, string? err
function M.fs_copyfile(path, new_path, flags)
    return coro.await(f3, uv.fs_copyfile, path, new_path, flags)
end

---@param fd integer
---@return uv.aliases.fs_stat_table? stat, string? err
function M.fs_fstat(fd)
    return coro.await(f1, uv.fs_fstat, fd)
end

---@param path string
---@param new_path string
---@return boolean? success, string? err
function M.fs_link(path, new_path)
    return coro.await(f2, uv.fs_link, path, new_path)
end

---@param path string
---@param new_path string
---@param flags { dir?: boolean, junction?: boolean }?
---@return boolean? success, string? err
function M.fs_symlink(path, new_path, flags)
    return coro.await(f3, uv.fs_symlink, path, new_path, flags)
end

---@param path string
---@param mode integer
---@return boolean? success, string? err
function M.fs_mkdir(path, mode)
    return coro.await(f2, uv.fs_mkdir, path, mode)
end

---@param path string
---@param flags string | integer
---@param mode integer
---@return integer? fd, string? err
function M.fs_open(path, flags, mode)
    return coro.await(f3, uv.fs_open, path, flags, mode)
end

---@param path string
---@param entries integer?
---@return luv_dir_t? dir, string? err
function M.fs_opendir(path, entries)
    return coro.await(function(resume)
        ---@diagnostic disable-next-line: param-type-mismatch
        uv.fs_opendir(path, create_callback(resume), entries)
    end)
end

---@param fd integer
---@param size integer
---@param offset integer?
---@return string? data, string? err
function M.fs_read(fd, size, offset)
    return coro.await(f3, uv.fs_read, fd, size, offset)
end

---@param dir luv_dir_t
---@return { name: string, type: string }[]? entries, string? err
function M.fs_readdir(dir)
    return coro.await(f1, uv.fs_readdir, dir)
end

---@param path string
---@return string? path, string? err
function M.fs_realpath(path)
    return coro.await(f1, uv.fs_realpath, path)
end

---@param path string
---@param new_path string
---@return boolean? success, string? err
function M.fs_rename(path, new_path)
    return coro.await(f2, uv.fs_rename, path, new_path)
end

---@param path string
---@return uv.aliases.fs_stat_table? success, string? err
function M.fs_stat(path)
    return coro.await(f1, uv.fs_stat, path)
end

---@param fd integer
---@param data uv.aliases.buffer
---@param offset integer?
---@return integer? bytes_written, string? err
function M.fs_write(fd, data, offset)
    return coro.await(f3, uv.fs_write, fd, data, offset)
end

---@param path string
---@return boolean? success, string? err
function M.fs_rmdir(path)
    return coro.await(f1, uv.fs_rmdir, path)
end

---@param path string
---@return boolean? success, string? err
function M.fs_unlink(path)
    return coro.await(f1, uv.fs_unlink, path)
end

return M
