-- Read file tool for Luna

local M = {}

local config = require("core.config")
local file_access_tracker = require("core.file_access_tracker")

local DEFAULT_READ_LIMIT = 150
local MAX_LINE_LENGTH = 2000

function M._check_sandbox(path, print_message)
    print_message = print_message ~= false
    
    if config.sandbox_disabled() then
        return true
    end
    
    if not path then
        return true
    end
    
    -- Simple sandbox: only allow files in current dir
    local handle = io.popen("pwd")
    local current_dir = handle:read("*a"):gsub("%s+$", "")
    handle:close()
    
    local abs_path = nil
    local h = io.popen("realpath '" .. path:gsub("'", "'\\''") .. "'")
    abs_path = h:read("*a"):gsub("%s+$", "")
    h:close()
    
    if abs_path ~= current_dir and not (string.sub(abs_path, 1, #current_dir + 1) == current_dir .. "/") then
        return false
    end
    
    return true
end

function M.execute(args)
    local path = args.path
    local offset = args.offset or 0
    local limit = args.limit or DEFAULT_READ_LIMIT
    
    if not path then
        error("Path is required")
    end
    
    if not M._check_sandbox(path) then
        local h = io.popen("pwd")
        local current_dir = h:read("*a"):gsub("%s+$", "")
        h:close()
        error('Path: ' .. path .. '\n[x] Sandbox: trying to access "' .. path .. '" outside current directory')
    end
    
    -- Check if file exists
    local h = io.popen("test -f '" .. path:gsub("'", "'\\''") .. "' && echo exists")
    local exists = h:read("*a"):gsub("%s+$", "") == "exists"
    h:close()
    
    if not exists then
        error("File not found: " .. path)
    end
    
    -- Read file
    local f, err = io.open(path, "r")
    if not f then
        error("Cannot read file: " .. err)
    end
    
    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()
    
    -- Record that this file was read (like v3)
    file_access_tracker.record_read(path)
    
    -- Apply offset and limit
    if offset >= #lines then
        return {
            tool = "read_file",
            friendly = "File " .. path .. " has " .. #lines .. " lines, but offset " .. offset .. " is beyond end of file",
            detailed = "Cannot read file '" .. path .. "'. Requested offset " .. offset .. " but file only has " .. #lines .. " lines."
        }
    end
    
    local end_index = math.min(offset + limit, #lines)
    local selected_lines = {}
    for i = offset + 1, end_index do  -- Lua is 1-indexed
        table.insert(selected_lines, lines[i])
    end
    
    -- Format with line numbers
    local formatted_lines = {}
    local truncated_count = 0
    for i, line in ipairs(selected_lines) do
        local truncated = false
        if #line > MAX_LINE_LENGTH then
            line = line:sub(1, MAX_LINE_LENGTH) .. ("... (%d chars total)"):format(#line)
            truncated = true
        end
        table.insert(formatted_lines, ("[%d] %s"):format(offset + i, line))
        if truncated then
            truncated_count = truncated_count + 1
        end
    end
    
    local formatted_content = table.concat(formatted_lines, "\n")
    
    local friendly_msg = ("Read %d lines from %s"):format(#selected_lines, path)
    if offset > 0 or end_index < #lines then
        friendly_msg = friendly_msg .. (" (showing lines %d-%d of %d)"):format(offset + 1, end_index, #lines)
    end
    
    return {
        tool = "read_file",
        friendly = friendly_msg,
        detailed = formatted_content
    }
end

function M.format_arguments(args)
    local path = args.path or "(unknown)"
    local offset = args.offset or 0
    local limit = args.limit or DEFAULT_READ_LIMIT
    
    local lines = {"Path: " .. path}
    
    if offset ~= 0 then
        table.insert(lines, "Offset: " .. offset)
    end
    
    if limit ~= DEFAULT_READ_LIMIT then
        table.insert(lines, "Limit: " .. limit)
    end
    
    return table.concat(lines, "\n  ")
end

function M.validate_arguments(args)
    if not args.path or type(args.path) ~= "string" then
        error("read_file requires \"path\" argument (string)")
    end
end

function M.generate_preview(args)
    -- No preview needed for read_file (like v3)
    return nil
end

-- Tool definition
M.TOOL_DEFINITION = {
    type = "internal",
    auto_approved = true,
    approval_excludes_arguments = false,
    description = "Reads the content from a specified file path.",
    parameters = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "The file system path to read from.",
            },
            offset = {
                type = "integer",
                description = "The line number to start reading from (default: 0).",
                default = 0,
            },
            limit = {
                type = "integer",
                description = ("The number of lines to read (default: %d, can be increased to read more)."):format(DEFAULT_READ_LIMIT),
                default = DEFAULT_READ_LIMIT,
            },
        },
        required = {"path"},
    },
}

M.TOOL_DEFINITION.execute = M.execute
M.TOOL_DEFINITION.formatArguments = M.format_arguments
M.TOOL_DEFINITION.validateArguments = M.validate_arguments
M.TOOL_DEFINITION.generatePreview = M.generate_preview

-- Module-level aliases for 1-1 parity with Python
M.formatArguments = M.format_arguments
M.validateArguments = M.validate_arguments
M.generatePreview = M.generate_preview

return M
