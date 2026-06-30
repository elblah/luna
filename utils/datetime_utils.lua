-- Date and time utilities
-- Ported from Python utils/datetime_utils.py

local M = {}

-- High-precision wall clock via LuaJIT FFI (fast, no subprocess)
-- clock_gettime(CLOCK_MONOTONIC, ...) for monotonic intervals
-- Works on Linux, macOS, Termux, and any POSIX system with LuaJIT
local _ffi = nil
local _have_ffi_clock = false
local _ts = nil
local _CLOCK_MONOTONIC = 1

-- Initialize FFI clock_gettime at module load
pcall(function()
    _ffi = require("ffi")
    _ffi.cdef[[
        struct timespec { long tv_sec; long tv_nsec; };
        int clock_gettime(int clk_id, struct timespec *tp);
    ]]
    _ts = _ffi.new("struct timespec")
    -- Verify it works
    if _ffi.C.clock_gettime(_CLOCK_MONOTONIC, _ts) == 0 then
        _have_ffi_clock = true
    end
end)

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
-- Priority: FFI clock_gettime (fast) > io.popen fallback (slow)
function M.get_time()
    if _have_ffi_clock then
        _ffi.C.clock_gettime(_CLOCK_MONOTONIC, _ts)
        return tonumber(_ts.tv_sec) + tonumber(_ts.tv_nsec) / 1e9
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