-- Date and time utilities
-- Ported from Python utils/datetime_utils.py

local M = {}

-- Check for socket availability at module load
local socket = (function()
    local ok, socket = pcall(require, "socket")
    if ok and socket then
        return socket
    end
    return nil
end)()

function M.create_file_timestamp()
    local t = os.time()
    local date = os.date("!*t", t)
    local iso = os.date("%Y-%m-%dT%H-%M-%S", t)
    return iso:sub(1, 19)
end

function M.create_timestamp_filename(prefix, extension)
    prefix = prefix or "file"
    extension = extension or ""
    if extension ~= "" and extension:sub(1, 1) ~= "." then
        extension = "." .. extension
    end
    local timestamp = M.create_file_timestamp()
    return prefix .. "-" .. timestamp .. extension
end

function M.get_current_iso_datetime()
    return os.date("!%Y-%m-%dT%H:%M:%S", os.time()) .. "Z"
end

-- Format matching Python: 2026-06-19_01:50:06
function M.get_stats_timestamp()
    return os.date("!%Y-%m-%d_%H:%M:%S")
end

-- Get wall time in seconds with nanosecond precision
function M.get_time()
    if socket then
        return socket.gettime()
    end
    local f = io.popen('date +%s%N')
    local t = f:read("*all")
    f:close()
    return tonumber(t) / 1e9
end

-- Round to 3 decimal places for cleaner output
function M.round_time(t)
    return math.floor(t * 1000 + 0.5) / 1000
end

return M