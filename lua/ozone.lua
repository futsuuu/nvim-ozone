local coro = require("ozone.x.coro")

local Build = require("ozone.build")
local Config = require("ozone.config")

local build_instance = Build.new()
local config = Config.new()

---@class ozone
local ozone = {}

---@class ozone.CleanOpts
---@field all? boolean

---@param opts? ozone.CleanOpts
---@return nil
function ozone.clean(opts)
    opts = opts or {}
    build_instance:clean(opts)
    config:clean(opts)
end

---@class ozone.PluginSpec
--- Plugin directory path
---@field path? string
--- Git repository URL
---@field url? string
--- Git ref (branch, tag, or revision)
---@field version? string
--- Plugin names this plugin depends on
---@field deps? string[]

---@param specs table<string, ozone.PluginSpec>
---@return nil
function ozone.add(specs)
    for name, spec in pairs(specs) do
        local ok, add_err = pcall(config.add_plugin, config, name, spec)
        if not ok then
            build_instance:err("plugin %q: %s", name, add_err)
        end
    end
end

---@return string[] errors
function ozone.errors()
    return build_instance:get_errors()
end

---@return nil
local function report_build_errors()
    local errors = build_instance:get_errors()
    if #errors == 0 then
        return
    end

    vim.api.nvim_echo({ { "[ozone] build errors", "WarningMsg" } }, true, {})
    for _, message in ipairs(errors) do
        vim.api.nvim_echo({ { message, "WarningMsg" } }, true, {})
    end
end

---@return nil
function ozone.run()
    assert(vim.v.vim_did_enter == 0)
    coro.wait(function()
        build_instance:clear_errors()
        config:load()
        local script = build_instance:generate_script(config)
        if script then
            local chunk, load_err = loadfile(script)
            if not chunk then
                build_instance:err("failed to load generated script %q: %s", script, load_err)
            else
                chunk()
            end
        end
        report_build_errors()
    end)
end

---@return nil
function ozone.update()
    coro.wait(function()
        build_instance:clear_errors()
        config:load()
        build_instance:update_lockfile(config)
        report_build_errors()
    end)
end

return ozone
