---@class ozone.Fetcher
local Fetcher = {}
---@private
Fetcher.__index = Fetcher

---@param source_kind string
---@return ozone.Fetcher
function Fetcher.new(source_kind)
    if source_kind == "git" then
        return require("ozone.fetcher.git").new()
    end

    error(("unsupported source kind: %s"):format(source_kind))
end

---@class ozone.Fetcher.Error
---@field code ozone.Fetcher.ErrorCode
---@field message string
---@field source_error? string

---@alias ozone.Fetcher.ErrorCode
---| "checkout_failed"
---| "clone_failed"
---| "fetch_failed"
---| "hash_resolution_failed"
---| "invalid_install_path"

---@param code ozone.Fetcher.ErrorCode
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

return Fetcher
