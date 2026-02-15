local coro = require("ozone.x.coro")

local M = {}

---@param cmd string[]
---@param opts? vim.SystemOpts
---@return vim.SystemCompleted? result
---@return string? err
local function run_system(cmd, opts)
    return coro.await(function(resume)
        local ok, start_err = pcall(vim.system, cmd, opts or {}, function(result)
            resume(result, nil)
        end)
        if not ok then
            resume(nil, tostring(start_err))
        end
    end)
end

---@param result vim.SystemCompleted
---@return string stdout
---@return string stderr
local function read_outputs(result)
    local stdout = type(result.stdout) == "string" and result.stdout or ""
    local stderr = type(result.stderr) == "string" and result.stderr or ""
    return stdout, stderr
end

---@param result vim.SystemCompleted
---@return boolean
local function is_success(result)
    return result.code == 0 and result.signal == 0
end

---@param path string
---@param version string
---@return boolean? success
---@return string? err
function M.checkout(path, version)
    local result, system_err = run_system({
        "git",
        "-C",
        path,
        "checkout",
        version,
    }, { text = true })
    if not result then
        return nil,
            ("checkout failed: %s at %s: %s"):format(version, path, system_err or "unknown error")
    end

    if not is_success(result) then
        local stdout, stderr = read_outputs(result)
        return nil,
            ("checkout failed: %s at %s (code=%d, signal=%d)%s%s"):format(
                version,
                path,
                result.code,
                result.signal,
                stdout ~= "" and ("\n---- stdout ----\n" .. stdout) or "",
                stderr ~= "" and ("\n---- stderr ----\n" .. stderr) or ""
            )
    end

    return true, nil
end

---@param url string
---@param path string
---@return boolean? success
---@return string? err
function M.clone(url, path)
    local result, system_err = run_system({
        "git",
        "clone",
        "--filter=blob:none",
        url,
        path,
    }, { text = true })
    if not result then
        return nil, ("clone failed: %s -> %s: %s"):format(url, path, system_err or "unknown error")
    end

    if not is_success(result) then
        local stdout, stderr = read_outputs(result)
        return nil,
            ("clone failed: %s -> %s (code=%d, signal=%d)%s%s"):format(
                url,
                path,
                result.code,
                result.signal,
                stdout ~= "" and ("\n---- stdout ----\n" .. stdout) or "",
                stderr ~= "" and ("\n---- stderr ----\n" .. stderr) or ""
            )
    end

    return true, nil
end

return M
