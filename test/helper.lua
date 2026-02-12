local coro = require("ozone.x.coro")
local fs = require("ozone.x.fs")

local helper = {}

---@param entries? table<string, string>
---@return string root_dir
function helper.temp_dir(entries)
    return coro.block_on(function()
        local root_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), fs.temp_name())
        assert(fs.create_dir_all(root_dir))
        for rel_path, content in pairs(entries or {}) do
            local file_path = vim.fs.joinpath(root_dir, rel_path)
            assert(fs.create_dir_all(vim.fs.dirname(file_path)))
            assert(fs.write_file(file_path, content))
        end
        return root_dir
    end)
end

return helper
