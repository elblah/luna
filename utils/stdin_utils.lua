-- Stdin utilities
-- Ported from Python utils/stdin_utils.py

local M = {}

function M.read_stdin_as_string()
    -- In Lua, we can't easily check if stdin is a tty
    -- We read by attempting to read from stdin
    local handle = io.stdin
    if handle then
        local content = handle:read("*a")
        if content and content ~= "" then
            return content
        end
    end
    return ""
end

function M.is_stdin_piped()
    -- Heuristic: if we can seek, it's not a pipe
    local handle = io.stdin
    if handle then
        local pos, err = handle:seek()
        if err then
            return true  -- seek failed, likely a pipe
        end
    end
    return false
end

return M
