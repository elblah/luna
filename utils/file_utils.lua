-- Cross-platform file operations
-- Ported from Python utils/file_utils.py

local os = require("os")

local M = {}

-- Module-level state
local _current_dir = os.getenv("PWD") or "."

local function get_relative_path(path)
    if not path then
        return "."
    end

    -- Simple relative path calculation
    local current = _current_dir
    if not current:match("/$") then
        current = current .. "/"
    end

    -- If path starts with current dir, extract relative part
    if path:sub(1, #current) == current then
        return path:sub(#current + 1)
    end

    return path
end

function M.get_current_dir()
    return _current_dir
end

function M.get_relative_path(path)
    return get_relative_path(path)
end

function M.is_within_sandbox(path)
    local config = require("core.config")

    if config.sandbox_disabled() then
        return true
    end

    if not path then
        return true
    end

    -- Check if path is within current directory
    local abs_path = path
    local abs_current = _current_dir
    if not abs_current:match("/$") then
        abs_current = abs_current .. "/"
    end

    -- Simple check: path must start with current dir
    if abs_path:sub(1, #abs_current) == abs_current then
        return true
    end

    -- Check if path is a subdirectory
    local rel = get_relative_path(path)
    if rel ~= path and not rel:match("^%.%./") then
        return true
    end

    return false
end

function M.check_sandbox(path, context)
    return M.is_within_sandbox(path)
end

function M.safe_read(path, limit, offset)
    if not M.is_within_sandbox(path) then
        return nil, "Access denied: path outside sandbox"
    end

    local f, err = io.open(path, "r")
    if not f then
        return nil, "Cannot open file: " .. tostring(err)
    end

    local content
    if offset and offset > 0 then
        -- Skip offset lines
        for i = 1, offset do
            f:read("*l")
        end
        content = f:read(limit or "*all")
    else
        content = f:read(limit or "*all")
    end
    f:close()

    return content
end

function M.safe_write(path, content)
    if not M.is_within_sandbox(path) then
        return false, "Access denied: path outside sandbox"
    end

    local f, err = io.open(path, "w")
    if not f then
        return false, "Cannot open file: " .. tostring(err)
    end

    f:write(content)
    f:close()
    return true
end

-- Track files read by AI requests (parity with Python's _read_files)
local _read_files = {}

function M.file_exists(path)
    if not path then return false end
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

-- Create a directory (and parents) with proper shell quoting for path safety
function M.mkdir_p(dir)
    if not dir or dir == "" or dir == "." then return true end
    local cmd = "mkdir -p '" .. tostring(dir):gsub("'", "'\\''") .. "' 2>/dev/null"
    os.execute(cmd)
    return true
end

-- Ensure parent directory of a file path exists
function M.ensure_parent_dir(filepath)
    if not filepath then return false end
    local dir = require("utils.path_utils").dirname(filepath)
    if dir and dir ~= "." then
        M.mkdir_p(dir)
    end
    return true
end

-- Read a file without sandbox check (internal use)
function M.read_file(path)
    if not path then
        return nil, "No path provided"
    end
    local f, err = io.open(path, "r")
    if not f then
        return nil, "Error reading file '" .. tostring(path) .. "': " .. tostring(err)
    end
    local content = f:read("*a")
    f:close()
    _read_files[path] = true
    return content
end

-- Read a file with sandbox check (AI requests only)
function M.read_file_with_sandbox(path)
    if not M.is_within_sandbox(path) then
        return nil, "Access denied: path outside sandbox"
    end
    return M.read_file(path)
end

-- Write a file without sandbox check (internal use)
function M.write_file(path, content)
    if not path then
        return nil, "No path provided"
    end
    local f, err = io.open(path, "w")
    if not f then
        return nil, "Error writing file '" .. tostring(path) .. "': " .. tostring(err)
    end
    f:write(content or "")
    f:close()
    return "Successfully wrote " .. tostring(path)
end

-- Write a file with sandbox check (AI requests only)
function M.write_file_with_sandbox(path, content)
    if not M.is_within_sandbox(path) then
        return nil, "Access denied: path outside sandbox"
    end
    return M.write_file(path, content)
end

-- List directory contents (parity with Python's list_directory)
function M.list_directory(path)
    if not path then path = "." end
    if not M.is_within_sandbox(path) then
        return nil, "Access denied: path outside sandbox"
    end
    local handle = io.popen("ls -1 -a " .. string.format("%q", path) .. " 2>/dev/null")
    if not handle then
        return nil, "Cannot list directory"
    end
    local entries = {}
    for entry in handle:lines() do
        table.insert(entries, entry)
    end
    handle:close()
    return entries
end

-- Get set of files read by AI requests
function M.get_read_files()
    local result = {}
    for path in pairs(_read_files) do
        table.insert(result, path)
    end
    return result
end

return M
