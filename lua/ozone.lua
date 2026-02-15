local coro = require("ozone.x.coro")

local Build = require("ozone.build")

local build_instance = Build.new()

---@class ozone
local ozone = {}

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

---@param specs table<string, ozone.Build.PluginSpec>
---@return nil
function ozone.add(specs)
    for name, spec in pairs(specs) do
        build_instance:add_plugin(name, spec)
    end
end

---@return string[] errors
function ozone.errors()
    return build_instance:get_errors()
end

---@return nil
function ozone.run()
    assert(vim.v.vim_did_enter == 0)
    coro.wait(function()
        -- TODO: evaluate all build scripts
        require("_build")
        local script = build_instance:generate_script()
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

return ozone
