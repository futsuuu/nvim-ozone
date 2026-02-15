local helper = {}

---@param cmd string[]
---@return nil
local function run_system(cmd)
    local output = vim.fn.system(cmd)
    assert(vim.v.shell_error == 0, output)
end

---@param root_dir string
---@param entries? table<string, string>
---@return nil
local function write_entries(root_dir, entries)
    for rel_path, content in pairs(entries or {}) do
        local file_path = vim.fs.joinpath(root_dir, rel_path)
        assert(1 == vim.fn.mkdir(vim.fs.dirname(file_path), "p"))
        local file = assert(io.open(file_path, "w"))
        assert(file:write(content))
        assert(file:close())
    end
end

---@param entries? table<string, string>
---@return string root_dir
function helper.temp_dir(entries)
    local root_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), vim.fs.basename(os.tmpname()))
    assert(1 == vim.fn.mkdir(root_dir, "p"))
    write_entries(root_dir, entries)
    return root_dir
end

---@param root_dir string
---@param ref? string
---@return string
function helper.git_rev(root_dir, ref)
    local output = vim.fn.system({ "git", "-C", root_dir, "rev-parse", ref or "HEAD" })
    assert(vim.v.shell_error == 0, output)
    return vim.trim(output)
end

---@param entries? table<string, string>
---@return string root_dir
function helper.git_repo(entries)
    local root_dir = helper.temp_dir(entries)
    run_system({ "git", "-C", root_dir, "init" })
    run_system({ "git", "-C", root_dir, "add", "." })
    run_system({
        "git",
        "-C",
        root_dir,
        "-c",
        "user.name=nvim-ozone-test",
        "-c",
        "user.email=nvim-ozone-test@example.com",
        "commit",
        "-m",
        "init",
    })
    return root_dir
end

---@param root_dir string
---@param entries table<string, string>
---@param message? string
---@return string rev
function helper.git_commit(root_dir, entries, message)
    write_entries(root_dir, entries)
    run_system({ "git", "-C", root_dir, "add", "." })
    run_system({
        "git",
        "-C",
        root_dir,
        "-c",
        "user.name=nvim-ozone-test",
        "-c",
        "user.email=nvim-ozone-test@example.com",
        "commit",
        "-m",
        message or "update",
    })
    return helper.git_rev(root_dir)
end

return helper
