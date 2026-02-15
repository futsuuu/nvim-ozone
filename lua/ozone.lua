local Build = require("ozone.build")
local coro = require("ozone.x.coro")

local build_instance = Build.new()

---@class ozone
local ozone = {}

---@param specs table<string, ozone.Build.PluginSpec>
---@return nil
function ozone.add(specs)
    for name, spec in pairs(specs) do
        build_instance:add_plugin(name, spec)
    end
end

---@return nil
function ozone.run()
    assert(vim.v.vim_did_enter == 0)
    coro.wait(function()
        -- TODO: evaluate all build scripts
        require("_build")
        local script = build_instance:generate_script()
        local chunk = loadfile(script)
        if chunk then
            chunk()
        end
    end)
end

return ozone
