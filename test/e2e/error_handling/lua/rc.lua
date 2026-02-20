---@param haystack string
---@param needle string
---@return boolean
local function contains(haystack, needle)
    return string.find(haystack, needle, 1, true) ~= nil
end

assert(vim.g.error_handling_ok_count == 1)

---@type ozone?
local ozone = package.loaded["ozone"]
if not ozone then
    return
end

local errors = ozone.errors()
assert(#errors == 1)
assert(contains(errors[1], 'plugin "clone_failure" clone failed'))
