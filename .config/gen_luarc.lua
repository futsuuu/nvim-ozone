local config = {
    ["$schema"] = "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
    runtime = {
        version = _G.jit and "LuaJIT" or _VERSION,
        pathStrict = true,
        path = {
            "${workspaceFolder}/?.lua",
            "lua/?.lua",
            "lua/?/init.lua",
        },
    },
    workspace = {
        checkThirdParty = false,
        library = {
            vim.env.VIMRUNTIME,
        },
        ignoreDir = {},
    },
    hint = {
        awaitPropagate = true,
    },
    type = {
        checkTableShape = true,
    },
    diagnostics = {
        groupFileStatus = {
            await = "Any",
            strict = "Any",
            strong = "Any",
            ["type-check"] = "Any",
        },
        unusedLocalExclude = { "_*" },
    },
}

do
    local library_path = "./.tmp/luv/library"
    if not vim.uv.fs_stat(library_path) then
        -- idk why, but the meta file of luv included in this is better than one bundled in Neovim.
        vim.fn.system({
            "git",
            "clone",
            "--depth=1",
            "https://github.com/Bilal2453/luvit-meta.git",
            "./.tmp/luvit",
        })
        vim.fn.mkdir(library_path, "p")
        assert(vim.uv.fs_link("./.tmp/luvit/library/uv.lua", "./.tmp/luv/library/luv.lua"))
    end
    table.insert(config.workspace.library, library_path)
    table.insert(config.workspace.ignoreDir, vim.fs.joinpath(vim.env.VIMRUNTIME, "lua", "uv"))
end

---@param path string
---@return string?
local function read_file(path)
    local file = io.open(path)
    if file then
        local data = file:read("*a")
        assert(file:close())
        return data
    end
end

local json_encoded = vim.json.encode(config) .. "\n"
for _, path in ipairs(arg) do
    local old = read_file(path)
    if old and vim.deep_equal(vim.json.decode(old), config) then
        io.stderr:write("skip: ", path, "\n")
    else
        io.stderr:write("write: ", path, "\n")
        local file = assert(io.open(path, "w"))
        assert(file:write(json_encoded))
        assert(file:close())
    end
end
