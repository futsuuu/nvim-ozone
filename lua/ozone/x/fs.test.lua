local runner = require("test.runner")

local fs = require("ozone.x.fs")
local helper = require("test.helper")

runner.add("write_file() and read_file() round-trip file contents", function()
    local root_dir = helper.temp_dir()
    local path = vim.fs.joinpath(root_dir, "hello.txt")
    local ok, write_err = fs.write_file(path, "hello\nworld")
    assert(ok, write_err)

    local data, read_err = fs.read_file(path)
    assert(read_err == nil, read_err)
    assert(data == "hello\nworld")
end)

runner.add("read_file() returns an error for a missing path", function()
    local root_dir = helper.temp_dir()
    local data, err = fs.read_file(vim.fs.joinpath(root_dir, "missing.txt"))
    assert(data == nil)
    assert(type(err) == "string")
end)

runner.add("write_file() returns an error if parent directory does not exist", function()
    local root_dir = helper.temp_dir()
    local path = vim.fs.joinpath(root_dir, "missing", "hello.txt")
    local ok, err = fs.write_file(path, "hello")
    assert(ok == nil)
    assert(type(err) == "string")
end)

runner.add("create_dir_all() creates nested directories and is idempotent", function()
    local root_dir = helper.temp_dir()
    local path = vim.fs.joinpath(root_dir, "a", "b", "c")
    local ok1, err1 = fs.create_dir_all(path)
    assert(ok1, err1)
    assert(fs.is_dir(path))

    local ok2, err2 = fs.create_dir_all(path)
    assert(ok2, err2)
    assert(fs.is_dir(path))
end)

runner.add("exists(), is_dir(), and is_file() classify paths", function()
    local root_dir = helper.temp_dir({
        ["file.txt"] = "content",
        ["dir/child.txt"] = "content",
    })
    local file_path = vim.fs.joinpath(root_dir, "file.txt")
    local missing_path = vim.fs.joinpath(root_dir, "missing")

    assert(fs.exists(root_dir))
    assert(fs.is_dir(root_dir))
    assert(not fs.is_file(root_dir))

    assert(fs.exists(file_path))
    assert(fs.is_file(file_path))
    assert(not fs.is_dir(file_path))

    assert(not fs.exists(missing_path))
    assert(not fs.is_file(missing_path))
    assert(not fs.is_dir(missing_path))
end)

runner.add("read_dir() iterates entries with names and types", function()
    local root_dir = helper.temp_dir({
        ["foo.txt"] = "content",
        ["nested/bar.txt"] = "content",
    })
    local read_dir, err = fs.read_dir(root_dir)
    assert(read_dir, err)

    local types_by_name = {} ---@type table<string, string>
    for i, entry in read_dir:iter() do
        if not i then
            error(entry)
        end
        types_by_name[entry.name] = entry.type
    end

    assert(types_by_name["foo.txt"] == "file")
    assert(types_by_name["nested"] == "directory")
end)

runner.add("remove_file() and remove_dir() remove existing paths", function()
    local root_dir = helper.temp_dir({
        ["delete-file.txt"] = "file",
        ["delete-dir/child.txt"] = "child",
    })
    local file_path = vim.fs.joinpath(root_dir, "delete-file.txt")
    local nested_file_path = vim.fs.joinpath(root_dir, "delete-dir", "child.txt")
    local dir_path = vim.fs.joinpath(root_dir, "delete-dir")

    local ok_file, err_file = fs.remove_file(file_path)
    assert(ok_file, err_file)
    assert(not fs.exists(file_path))

    assert(fs.remove_file(nested_file_path))
    local ok_dir, err_dir = fs.remove_dir(dir_path)
    assert(ok_dir, err_dir)
    assert(not fs.exists(dir_path))
end)

runner.add("remove_dir_all() recursively removes a directory tree", function()
    local root_dir = helper.temp_dir({
        ["remove-me/one.txt"] = "one",
        ["remove-me/nested/two.txt"] = "two",
    })
    local dir_path = vim.fs.joinpath(root_dir, "remove-me")

    local ok, err = fs.remove_dir_all(dir_path)
    assert(ok, err)
    assert(not fs.exists(dir_path))
    assert(fs.exists(root_dir))
end)

runner.add("remove_dir_all() returns an error for a missing path", function()
    local root_dir = helper.temp_dir()
    local ok, err = fs.remove_dir_all(vim.fs.joinpath(root_dir, "missing"))
    assert(ok == nil)
    assert(type(err) == "string")
end)

runner.add("temp_name() returns a non-empty basename", function()
    local name = fs.temp_name()
    assert(type(name) == "string")
    assert(#name > 0)
    assert(vim.fs.basename(name) == name)
end)
