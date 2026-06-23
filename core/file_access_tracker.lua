-- File Access Tracker - Enforces read-before-edit safety rule
-- Ported from Python core/file_access_tracker.py

local M = {}

-- Class-style alias for 1-1 parity with Python's FileAccessTracker class
M.FileAccessTracker = M

-- Class variable (module-level in Lua)
local _read_files = {}

function M.record_read(path)
    _read_files[path] = true
end

function M.was_file_read(path)
    return _read_files[path] == true
end

function M.clear_state()
    _read_files = {}
end

function M.get_all_read_files()
    local result = {}
    for path, _ in pairs(_read_files) do
        table.insert(result, path)
    end
    return result
end

function M.get_read_count()
    local count = 0
    for _, _ in pairs(_read_files) do
        count = count + 1
    end
    return count
end

return M
