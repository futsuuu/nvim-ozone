---@param haystack string
---@param needle string
---@return boolean
local function contains(haystack, needle)
    return string.find(haystack, needle, 1, true) ~= nil
end

assert(vim.g.error_handling_ok_count == 1)
assert(vim.g.error_handling_duplicate_count == nil)
assert(vim.g.error_handling_invalid_name_count == nil)

---@type ozone?
local ozone = package.loaded["ozone"]
if not ozone then
    return
end

local errors = ozone.errors()
assert(#errors == 8)
local joined_errors = table.concat(errors, "\n")
assert(contains(joined_errors, 'plugin "invalid_spec":'))
assert(contains(joined_errors, "spec: expected table, got string"))
assert(contains(joined_errors, 'plugin "missing_source":'))
assert(contains(joined_errors, "source: expected `path` or `url` must be set"))
assert(contains(joined_errors, 'plugin "version_without_url":'))
assert(contains(joined_errors, "version_source: expected `version` requires `url`"))
assert(contains(joined_errors, 'plugin "invalid_url_type":'))
assert(contains(joined_errors, "url: expected non-empty string, got table"))
assert(contains(joined_errors, 'plugin "clone_failure" clone failed'))
assert(contains(joined_errors, 'plugin "invalid/name":'))
assert(contains(joined_errors, "name: expected plugin name (letters, digits, '_', '.', '-')"))
assert(contains(joined_errors, 'plugin "duplicate": duplicate name (definition #1)'))
assert(contains(joined_errors, 'plugin "duplicate": duplicate name (definition #2)'))
