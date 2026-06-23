-- Boolean parsing utilities

local M = {}

-- Truthy values: on, 1, yes, true, enable
local TRUTHY = {
    on = true,
    ["1"] = true,
    yes = true,
    enable = true,
}

-- Falsy values: off, 0, no, false, disable
local FALSY = {
    off = true,
    ["0"] = true,
    no = true,
    disable = true,
}

function M.parse_bool(s)
    if not s then return nil end
    s = tostring(s):lower()
    if s == "true" or s == "1" or s == "yes" or s == "on" or s == "enable" or s == "enabled" then
        return true
    elseif s == "false" or s == "0" or s == "no" or s == "off" or s == "disable" or s == "disabled" then
        return false
    end
    return nil
end

return M