---@class ozone.Fetcher
local Fetcher = {}
---@private
Fetcher.__index = Fetcher

---@class ozone.Fetcher.Error
---@field code string
---@field message string
---@field source_error? string

---@param code string
---@param message string
---@param source_error? string
---@return ozone.Fetcher.Error
function Fetcher.error(code, message, source_error)
    return {
        code = code,
        message = message,
        source_error = source_error,
    }
end

---@param err ozone.Fetcher.Error?
---@param fallback? string
---@return string
function Fetcher.format_error(err, fallback)
    if err == nil then
        return fallback or "unknown error"
    end

    if err.source_error and err.source_error ~= "" then
        return ("%s: %s"):format(err.message, err.source_error)
    end

    return err.message
end

---@param source_kind string
---@return ozone.Fetcher
function Fetcher.new(source_kind)
    if source_kind == "git" then
        local GitFetcher = require("ozone.fetcher.git")
        return GitFetcher.new()
    end

    error(("unsupported source kind: %s"):format(source_kind))
end

return Fetcher
