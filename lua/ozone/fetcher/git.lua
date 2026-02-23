local fs = require("ozone.x.fs")

local Fetcher = require("ozone.fetcher")
local git = require("ozone.git")

---@class ozone.fetcher.GitFetcher: ozone.Fetcher
local GitFetcher = {}
---@private
GitFetcher.__index = GitFetcher

---@return self
function GitFetcher.new()
    return setmetatable({}, GitFetcher)
end

---@param code string
---@param message string
---@param source_error? string
---@return ozone.Fetcher.Error
local function fetcher_error(code, message, source_error)
    return Fetcher.error(code, message, source_error)
end

---@param source ozone.Config.PluginSource.Git
---@return string? checkout_target
local function resolve_checkout_target(source)
    return source.hash or source.version
end

---@param path string
---@return boolean? success
---@return ozone.Fetcher.Error? err
local function validate_install_path(path)
    if not fs.exists(path) then
        return true, nil
    end

    if fs.is_dir(path) then
        return true, nil
    end

    return nil, fetcher_error("invalid_install_path", ("install path exists and is not a directory: %s"):format(path))
end

---@param source ozone.Config.PluginSource.Git
---@param path string
---@return boolean? success
---@return ozone.Fetcher.Error? err
function GitFetcher:install(source, path)
    local path_ok, path_err = validate_install_path(path)
    if not path_ok then
        return nil, path_err
    end

    if not fs.exists(path) then
        local clone_success, clone_err = git.clone(source.url, path)
        if not clone_success then
            return nil, fetcher_error("clone_failed", "clone failed", clone_err)
        end
    end

    local checkout_target = resolve_checkout_target(source)
    if checkout_target then
        local checkout_success, checkout_err = git.checkout(path, checkout_target)
        if not checkout_success then
            return nil, fetcher_error("checkout_failed", "checkout failed", checkout_err)
        end
    end

    return true, nil
end

---@param source ozone.Config.PluginSource.Git
---@param path string
---@return boolean? success
---@return ozone.Fetcher.Error? err
function GitFetcher:ensure_cloned(source, path)
    local path_ok, path_err = validate_install_path(path)
    if not path_ok then
        return nil, path_err
    end

    if fs.exists(path) then
        return true, nil
    end

    local clone_success, clone_err = git.clone(source.url, path)
    if not clone_success then
        return nil, fetcher_error("clone_failed", "clone failed", clone_err)
    end

    return true, nil
end

---@param path string
---@return boolean? success
---@return ozone.Fetcher.Error? err
function GitFetcher:fetch(path)
    local fetch_success, fetch_err = git.fetch(path)
    if not fetch_success then
        return nil, fetcher_error("fetch_failed", "fetch failed", fetch_err)
    end

    return true, nil
end

---@param source ozone.Config.PluginSource.Git
---@param path string
---@return string? hash
---@return ozone.Fetcher.Error? err
function GitFetcher:resolve_hash(source, path)
    local hash = nil ---@type string?
    local hash_err = nil ---@type string?
    if source.version then
        hash, hash_err = git.resolve_version_hash(path, source.version)
    else
        hash, hash_err = git.remote_head_hash(path)
    end

    if not hash then
        return nil, fetcher_error("hash_resolution_failed", "failed to resolve hash", hash_err)
    end

    return hash, nil
end

---@param path string
---@return string? hash
---@return ozone.Fetcher.Error? err
function GitFetcher:hash(path)
    local hash, hash_err = git.hash(path)
    if not hash then
        return nil, fetcher_error("hash_resolution_failed", "failed to resolve hash", hash_err)
    end

    return hash, nil
end

return GitFetcher
