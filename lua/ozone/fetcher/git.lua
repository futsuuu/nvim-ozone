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
    return source.revision or source.version
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
---@return string? revision
---@return ozone.Fetcher.Error? err
function GitFetcher:resolve_revision(source, path)
    local revision = nil ---@type string?
    local revision_err = nil ---@type string?
    if source.version then
        revision, revision_err = git.resolve_version_revision(path, source.version)
    else
        revision, revision_err = git.remote_head_revision(path)
    end

    if not revision then
        return nil, fetcher_error("revision_resolution_failed", "failed to resolve revision", revision_err)
    end

    return revision, nil
end

---@param path string
---@return string? revision
---@return ozone.Fetcher.Error? err
function GitFetcher:revision(path)
    local revision, revision_err = git.revision(path)
    if not revision then
        return nil, fetcher_error("revision_resolution_failed", "failed to resolve revision", revision_err)
    end

    return revision, nil
end

return GitFetcher
