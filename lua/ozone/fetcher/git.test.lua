local runner = require("test.runner")

local Fetcher = require("ozone.fetcher")
local GitFetcher = require("ozone.fetcher.git")
local coro = require("ozone.x.coro")
local helper = require("test.helper")

---@param cmd string[]
---@return nil
local function run_system(cmd)
    local output = vim.fn.system(cmd)
    assert(vim.v.shell_error == 0, output)
end

---@param url string
---@param version? string
---@param hash? string
---@return ozone.Config.PluginSource.Git
local function git_source(url, version, hash)
    return {
        kind = "git",
        url = url,
        version = version,
        hash = hash,
    }
end

runner.add("install() clones and checks out pinned hash", function()
    local repo_path = helper.git_repo({
        ["plugin/value.lua"] = [[
vim.g.fetcher_test_value = "v1"
]],
    })
    local pinned_hash = helper.git_rev(repo_path)
    helper.git_commit(repo_path, {
        ["plugin/value.lua"] = [[
vim.g.fetcher_test_value = "v2"
]],
    })

    local root_dir = helper.temp_dir()
    local install_path = vim.fs.joinpath(root_dir, "plugin")
    local fetcher = GitFetcher.new()
    local source = git_source(repo_path, nil, pinned_hash)

    local installed, install_err = coro.wait(function()
        return fetcher:install(source, install_path)
    end)
    assert(installed, Fetcher.format_error(install_err))
    assert(helper.git_rev(install_path) == pinned_hash)
end)

runner.add("ensure_cloned() clones once and is idempotent", function()
    local repo_path = helper.git_repo({
        ["plugin/value.lua"] = [[
vim.g.fetcher_clone_test = 1
]],
    })

    local root_dir = helper.temp_dir()
    local install_path = vim.fs.joinpath(root_dir, "plugin")
    local fetcher = GitFetcher.new()
    local source = git_source(repo_path)

    local first_ok, first_err = coro.wait(function()
        return fetcher:ensure_cloned(source, install_path)
    end)
    assert(first_ok, Fetcher.format_error(first_err))
    local first_hash = helper.git_rev(install_path)

    local second_ok, second_err = coro.wait(function()
        return fetcher:ensure_cloned(source, install_path)
    end)
    assert(second_ok, Fetcher.format_error(second_err))
    assert(helper.git_rev(install_path) == first_hash)
end)

runner.add("resolve_hash() resolves both version and remote head", function()
    local repo_path = helper.git_repo({
        ["plugin/versioned.lua"] = [[
vim.g.fetcher_versioned = "v1"
]],
    })
    local v1_hash = helper.git_rev(repo_path)
    run_system({ "git", "-C", repo_path, "tag", "v1" })
    local head_hash = helper.git_commit(repo_path, {
        ["plugin/versioned.lua"] = [[
vim.g.fetcher_versioned = "v2"
]],
    })

    local root_dir = helper.temp_dir()
    local install_path = vim.fs.joinpath(root_dir, "plugin")
    local fetcher = GitFetcher.new()
    local source = git_source(repo_path)

    local cloned, clone_err = coro.wait(function()
        return fetcher:ensure_cloned(source, install_path)
    end)
    assert(cloned, Fetcher.format_error(clone_err))

    local version_hash, version_err = coro.wait(function()
        return fetcher:resolve_hash(git_source(repo_path, "v1"), install_path)
    end)
    assert(version_hash, Fetcher.format_error(version_err))
    assert(version_hash == v1_hash)

    local remote_head_hash, remote_head_err = coro.wait(function()
        return fetcher:resolve_hash(source, install_path)
    end)
    assert(remote_head_hash, Fetcher.format_error(remote_head_err))
    assert(remote_head_hash == head_hash)
end)

runner.add("install() returns invalid_install_path for file destinations", function()
    local repo_path = helper.git_repo({
        ["plugin/value.lua"] = [[
vim.g.fetcher_invalid_path = true
]],
    })
    local root_dir = helper.temp_dir({
        ["not-a-dir"] = "file",
    })
    local invalid_path = vim.fs.joinpath(root_dir, "not-a-dir")
    local fetcher = GitFetcher.new()

    local installed, install_err = coro.wait(function()
        return fetcher:install(git_source(repo_path), invalid_path)
    end)
    assert(installed == nil)
    assert(install_err ~= nil)
    assert(install_err.code == "invalid_install_path")
end)

runner.add("fetch() returns fetch_failed for non-repository paths", function()
    local root_dir = helper.temp_dir({
        ["plain.txt"] = "file",
    })
    local non_repo_path = vim.fs.joinpath(root_dir, "plain.txt")
    local fetcher = GitFetcher.new()

    local fetched, fetch_err = coro.wait(function()
        return fetcher:fetch(non_repo_path)
    end)
    assert(fetched == nil)
    assert(fetch_err ~= nil)
    assert(fetch_err.code == "fetch_failed")
end)
