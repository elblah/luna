-- Path utilities for security and validation
-- Ported from Python utils/path_utils.py

local M = {}

function M.expand(path)
    if not path then return path end
    if path:sub(1, 1) == "~" then
        local home = os.getenv("HOME")
        if home then
            return home .. path:sub(2)
        end
    end
    return path
end

function M.is_safe_path(path)
    if not path then
        return true
    end
    -- Check for parent directory traversal
    if path:find("../") then
        return false
    end
    return true
end

function M.validate_path(path, context)
    context = context or "operation"
    if not M.is_safe_path(path) then
        local log = require("utils.log")
        log.warn("Sandbox: " .. context .. " trying to access \"" .. path .. "\" (contains parent traversal)")
        return false
    end
    return true
end

function M.validate_tool_path(path, tool_name)
    tool_name = tool_name or "tool"
    if not M.is_safe_path(path) then
        local log = require("utils.log")
        log.warn("Sandbox: " .. tool_name .. " trying to access \"" .. path .. "\" (contains parent traversal)")
        return false
    end
    return true
end

return M
