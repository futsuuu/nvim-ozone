local Script = require("ozone.script")
local fs = require("ozone.x.fs")

---@class ozone.Build.PluginSpec
--- Plugin directory path
---@field path string

---@class ozone.Build
---@field private _plugins table<string, ozone.Build.PluginSpec>
---@field private _output_path string
local Build = {}
---@private
Build.__index = Build

---@return self
function Build.new()
    return setmetatable({
        _plugins = {},
        _output_path = vim.fn.stdpath("data") .. "/ozone/main",
    }, Build)
end

---@param name string
---@param spec ozone.Build.PluginSpec
---@return nil
function Build:add_plugin(name, spec)
    self._plugins[name] = spec
end

---@return string path
function Build:generate_script()
    local script = Script.new()
    for _, spec in pairs(self._plugins) do
        if fs.is_dir(spec.path) then
            table.insert(script.rtp_prefix, spec.path)
            if fs.is_dir(spec.path .. "/after") then
                table.insert(script.rtp_suffix, spec.path .. "/after")
            end
        end
    end
    assert(fs.create_dir_all(vim.fs.dirname(self._output_path)))
    assert(fs.write_file(self._output_path, script:tostring()))
    return self._output_path
end

return Build
