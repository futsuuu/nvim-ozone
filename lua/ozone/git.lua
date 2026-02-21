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

---@param prefix string
---@param result vim.SystemCompleted
---@return string
local function format_system_failure(prefix, result)
    local stdout, stderr = read_outputs(result)
    local message = ("%s (code=%d, signal=%d)"):format(prefix, result.code, result.signal)

    if stdout ~= "" then
        message = message .. "\n---- stdout ----\n" .. stdout
    end
    if stderr ~= "" then
        message = message .. "\n---- stderr ----\n" .. stderr
    end

    return message
end

---@param result vim.SystemCompleted
---@return boolean
local function is_success(result)
    return result.code == 0 and result.signal == 0
end

---@param path string
---@param ref string
---@return string? revision
---@return string? err
function M.rev_parse(path, ref)
    local result, system_err = run_system({
        "git",
        "-C",
        path,
        "rev-parse",
        ref,
    }, { text = true })
    if not result then
        return nil, ("rev-parse failed: %s at %s: %s"):format(ref, path, system_err or "unknown error")
    end

    if not is_success(result) then
        return nil, format_system_failure(("rev-parse failed: %s at %s"):format(ref, path), result)
    end

    local stdout, _ = read_outputs(result)
    stdout = vim.trim(stdout)
    if stdout == "" then
        return nil, ("rev-parse failed: %s at %s: empty stdout"):format(ref, path)
    end
    return stdout, nil
end

---@param path string
---@return string? revision
---@return string? err
function M.revision(path)
    return M.rev_parse(path, "HEAD")
end

---@param path string
---@param version string
---@return string? revision
---@return string? err
function M.resolve_version_revision(path, version)
    local revision, rev_parse_err = M.rev_parse(path, version)
    if revision then
        return revision, nil
    end

    revision, rev_parse_err = M.rev_parse(path, "origin/" .. version)
    if revision then
        return revision, nil
    end

    return nil, rev_parse_err
end

---@param path string
---@return string? revision
---@return string? err
function M.remote_head_revision(path)
    return M.rev_parse(path, "origin/HEAD")
end

---@param path string
---@return boolean? success
---@return string? err
function M.fetch(path)
    local result, system_err = run_system({
        "git",
        "-C",
        path,
        "fetch",
        "--prune",
        "--tags",
    }, { text = true })
    if not result then
        return nil, ("fetch failed at %s: %s"):format(path, system_err or "unknown error")
    end

    if not is_success(result) then
        return nil, format_system_failure(("fetch failed at %s"):format(path), result)
    end

    return true, nil
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
        return nil, ("checkout failed: %s at %s: %s"):format(version, path, system_err or "unknown error")
    end

    if not is_success(result) then
        return nil, format_system_failure(("checkout failed: %s at %s"):format(version, path), result)
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
        return nil, format_system_failure(("clone failed: %s -> %s"):format(url, path), result)
    end

    return true, nil
end

return M
