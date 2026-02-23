local M = {}

M.META_PATH = vim.fs.joinpath(vim.fn.stdpath("state"), "update-meta.json")
M.REMOVE_REMOVED_FLAG_PATH = vim.fs.joinpath(vim.fn.stdpath("state"), "update-remove-removed")

---@param path string
---@return table?
function M.read_json(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local data = assert(file:read("*a"))
    assert(file:close())
    local ok, value_or_err = pcall(vim.json.decode, data)
    assert(ok, value_or_err)
    return value_or_err
end

---@param path string
---@param value table
---@return nil
function M.write_json(path, value)
    local dir_path = assert(vim.fs.dirname(path))
    assert(1 == vim.fn.mkdir(dir_path, "p"))
    local file = assert(io.open(path, "w"))
    assert(file:write(vim.json.encode(value)))
    assert(file:close())
end

return M
