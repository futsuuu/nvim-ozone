---@param haystack string
---@param needle string
---@return boolean
local function contains(haystack, needle)
    return string.find(haystack, needle, 1, true) ~= nil
end

assert(vim.g.error_handling_ok_count == 1)

local ozone = package.loaded["ozone"]
if not ozone then
    return
end

local errors = ozone.errors()
assert(#errors == 5)
local joined_errors = table.concat(errors, "\n")
assert(contains(joined_errors, 'plugin "invalid_spec" spec must be a table'))
assert(contains(joined_errors, 'plugin "missing_source" must define `path` or `url`'))
assert(contains(joined_errors, 'plugin "version_without_url": `version` requires `url`'))
assert(contains(joined_errors, 'plugin "invalid_url_type": `url` must be a string'))
assert(contains(joined_errors, 'plugin "clone_failure" clone failed'))
