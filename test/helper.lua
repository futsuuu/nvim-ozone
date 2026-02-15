local helper = {}

---@param entries? table<string, string>
---@return string root_dir
function helper.temp_dir(entries)
    local root_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), vim.fs.basename(os.tmpname()))
    assert(1 == vim.fn.mkdir(root_dir, "p"))
    for rel_path, content in pairs(entries or {}) do
        local file_path = vim.fs.joinpath(root_dir, rel_path)
        assert(1 == vim.fn.mkdir(vim.fs.dirname(file_path), "p"))
        local file = assert(io.open(file_path, "w"))
        assert(file:write(content))
        assert(file:close())
    end
    return root_dir
end

return helper
