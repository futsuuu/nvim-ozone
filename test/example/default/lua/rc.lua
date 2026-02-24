vim.cmd.colorscheme("robot")

do
    vim.o.clipboard = "unnamedplus"
    vim.o.cmdheight = 0
    vim.o.completeopt = "fuzzy,menu,menuone,noinsert"

    vim.o.laststatus = 3

    vim.o.number = true

    vim.o.scrolloff = 4
    vim.o.sidescrolloff = 8

    vim.o.splitbelow = true
    vim.o.splitkeep = "cursor"
    vim.o.splitright = true

    vim.o.virtualedit = "onemore"
    vim.o.wrap = false
end

vim.diagnostic.config({
    float = true,
    severity_sort = true,
    signs = false,
    update_in_insert = true,
    virtual_text = {
        prefix = "•",
    },
})

require("fidget").setup({
    progress = {
        display = {
            done_icon = "✓",
        },
    },
})

vim.lsp.enable({ "lua_ls" })

-- :help |lsp-attach|
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
        local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))
        if client:supports_method("textDocument/completion") then
            local chars = {}
            for i = 32, 126 do
                table.insert(chars, string.char(i))
            end
            client.server_capabilities.completionProvider.triggerCharacters = chars

            vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
        end
    end,
})

do
    require("insx.preset.standard").setup({
        fast_break = { enabled = true },
        fast_wrap = { enabled = true },
    })
    ---@type vim.api.keyset.get_keymap
    local insx_cr_map = vim.iter(vim.api.nvim_get_keymap("i"))
        :filter(function(map)
            return map.lhsraw == "\r"
        end)
        :totable()[1]
    vim.keymap.set("i", "<CR>", function()
        if vim.fn.pumvisible() == 1 then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-y>", true, false, true), "n", true)
        else
            assert(insx_cr_map.callback)()
        end
    end, { silent = true })
end

vim.keymap.set({ "i", "s" }, "<Tab>", function()
    return vim.snippet.active({ direction = 1 }) and "<Cmd>lua vim.snippet.jump(1)<CR>" or "<Tab>"
end, { expr = true, silent = true })
vim.keymap.set({ "i", "s" }, "<S-Tab>", function()
    return vim.snippet.active({ direction = -1 }) and "<Cmd>lua vim.snippet.jump(-1)<CR>" or "<S-Tab>"
end, { expr = true, silent = true })
