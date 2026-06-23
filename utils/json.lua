-- JSON wrapper: tries cjson, falls back to dkjson

local M = {}
local use_cjson = false

-- Try cjson first (faster, C-based)
local ok, cjson = pcall(require, "cjson")
if ok then
    use_cjson = true
    M.encode = cjson.encode
    M.decode = cjson.decode
else
    -- Fallback to dkjson (pure Lua, battle-tested)
    local dkjson = require("utils.dkjson")
    M.encode = dkjson.encode
    -- dkjson returns nil for invalid JSON instead of erroring
    -- Wrap decode to match cjson behavior (error on invalid)
    function M.decode(str)
        if type(str) ~= "string" or #str == 0 then
            error("empty or nil input")
        end
        local result = dkjson.decode(str)
        -- dkjson returns nil for invalid JSON like "{bad}"
        -- but also for literal "null", so check if input was "null"
        if result == nil and str ~= "null" then
            error("invalid json")
        end
        return result
    end
end

return M
