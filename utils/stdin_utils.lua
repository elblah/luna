-- Stdin utilities
-- Ported from Python utils/stdin_utils.py

local M = {}

-- Use FFI to call C isatty() for reliable TTY detection
local ffi = nil
local function is_stdin_tty()
    if ffi == nil then
        pcall(function()
            ffi = require("ffi")
            ffi.cdef("int isatty(int fd);")
        end)
    end
    if ffi then
        return ffi.C.isatty(0) == 1
    end
    -- Fallback: assume TTY if FFI not available
    return true
end
M.is_stdin_tty = is_stdin_tty

function M.read_stdin_as_string()
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
    return not is_stdin_tty()
end

return M
