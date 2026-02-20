io.stdout:write("version: NVIM v", tostring(vim.version()), "\n\n")
vim.opt.runtimepath:prepend(vim.uv.cwd())

local FILE = assert(vim.uv.fs_realpath(arg[0]))
local TEST_DIR = vim.fs.dirname(FILE)
local BASE_ENV = {
    NVIM_APPNAME = "default",
    XDG_CONFIG_HOME = vim.fs.joinpath(TEST_DIR, "e2e"),
    XDG_CACHE_HOME = vim.fs.abspath(".tmp/.cache/e2e"),
    XDG_DATA_HOME = vim.fs.abspath(".tmp/.local/share/e2e"),
    XDG_STATE_HOME = vim.fs.abspath(".tmp/.local/state/e2e"),
}

local coro = require("ozone.x.coro")

---@class test.Case
---@field name string
---@field fn async fun()
local Case = {}
---@private
Case.__index = Case

---@param name string
---@param fn async fun()
---@return test.Case
function Case.new(name, fn)
    return setmetatable({
        name = name,
        fn = fn,
    }, Case)
end

function Case:run()
    local full_name = debug.getinfo(self.fn --[[@as function]], "S").short_src
        .. " :: "
        .. self.name
    io.stderr:write(" start: ", full_name, "\n")
    -- TODO: handle errors
    coro.wait(self.fn)
    io.stderr:write("finish: ", full_name, "\n")
end

local M = {}

---@type test.Case[]
local cases = {}

---@param name string
---@param fn async fun()
function M.add(name, fn)
    table.insert(cases, Case.new(name, fn))
end

---@package
function M._main()
    for key, value in pairs(BASE_ENV) do
        io.stderr:write(key, "=", value, "\n")
        vim.uv.os_setenv(key, value)
    end
    io.stderr:write("\n")
    vim.fn.delete(BASE_ENV.XDG_CACHE_HOME, "rf")
    vim.fn.delete(BASE_ENV.XDG_DATA_HOME, "rf")
    vim.fn.delete(BASE_ENV.XDG_STATE_HOME, "rf")

    local test_files = vim.fs.find(function(name)
        return name:match("%.test%.lua$") ~= nil
    end, { path = "lua", limit = math.huge, type = "file" })
    io.stderr:write(#test_files, " test files found\n")
    for _, file_path in ipairs(test_files) do
        dofile(file_path)
    end

    local e2e_lua_dirs = vim.fs.find(function(name)
        return name == "lua"
    end, { path = "test/e2e", limit = math.huge, type = "directory" })
    io.stderr:write(#e2e_lua_dirs, " E2E tests found\n")
    for _, lua_dir in ipairs(e2e_lua_dirs) do
        local appname = assert(vim.fs.relpath("test/e2e", vim.fs.dirname(lua_dir)))
        table.insert(
            cases,
            Case.new("e2e/" .. appname, function()
                M._run_e2e(appname)
            end)
        )
    end

    io.stderr:write(#cases, " test cases collected\n")
    for _, case in ipairs(cases) do
        case:run()
    end
end

---@package
---@param name string
function M._run_e2e(name)
    local VIMRC = vim.fs.joinpath(TEST_DIR, "e2e", "init.lua")
    for i = 1, 2 do
        local stdout = {}
        local stderr = {}
        local obj ---@type vim.SystemObj
        obj = vim.system({
            vim.v.progpath,
            "--headless",
            "-u",
            VIMRC,
            "-i",
            "NONE",
            '+lua vim.cmd(vim.v.errmsg == "" and "qa!" or "cq!")',
        }, {
            env = { NVIM_APPNAME = name },
            text = true,
            stdout = function(err, data)
                assert(not err, err)
                if not data then
                    return
                end
                table.insert(stdout, data)
            end,
            stderr = function(err, data)
                assert(not err, err)
                if not data then
                    return
                end
                table.insert(stderr, data)
            end,
        })
        local status = obj:wait()
        if status.code ~= 0 or status.signal ~= 0 then
            io.stderr:write("\n")
            error(
                ("step %d: child process failed: %s: code = %d, signal = %d%s%s"):format(
                    i,
                    name,
                    status.code,
                    status.signal,
                    #stdout > 0 and ("\n---- stdout ----\n%s"):format(table.concat(stdout, "")) or "",
                    #stderr > 0 and ("\n---- stderr ----\n%s"):format(table.concat(stderr, "")) or ""
                )
            )
        end
    end
end

if not package.loaded["test.runner"] then
    package.loaded["test.runner"] = M
    M._main()
end

return M
