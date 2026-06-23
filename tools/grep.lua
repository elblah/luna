-- Grep tool for Luna

local M = {}

local config = require("core.config")

local DEFAULT_MAX_RESULTS = 100
local MAX_DETAILED_LINES = 50   -- Truncate detailed output by lines
local MAX_DETAILED_BYTES = 5000 -- Truncate detailed output by bytes

-- Helper to truncate detailed output by both lines and bytes
local function truncate_detailed(matches, friendly_text, extra_info)
    -- Build string with line limit
    local limit = math.min(MAX_DETAILED_LINES, #matches)
    local parts = {}
    for i = 1, limit do
        if matches[i] then
            parts[i] = matches[i]
        end
    end
    local truncated = table.concat(parts, "\n")
    
    if #matches > limit then
        truncated = truncated .. ("\n... and %d more matches (truncated, use more specific search)"):format(#matches - limit)
    end
    
    -- Apply byte limit
    if #truncated > MAX_DETAILED_BYTES then
        truncated = truncated:sub(1, MAX_DETAILED_BYTES) .. ("\n... truncated at %d bytes (use more specific search)"):format(MAX_DETAILED_BYTES)
    end
    
    return truncated
end

function M.validate_arguments(args)
    local text = args.text
    if not text or type(text) ~= "string" then
        error("grep requires \"text\" argument (string)")
    end
end

function M.format_arguments(args)
    local text = args.text or ""
    local path = args.path or "."
    local max_results = args.max_results or DEFAULT_MAX_RESULTS
    local context = args.context or 2
    
    local parts = {'Text: "' .. text .. '"'}
    if path and path ~= "." then
        table.insert(parts, ("Path: %s"):format(path))
    end
    if max_results ~= DEFAULT_MAX_RESULTS then
        table.insert(parts, ("Max results: %d"):format(max_results))
    end
    if context ~= 2 then
        table.insert(parts, ("Context: %d lines"):format(context))
    end
    
    return table.concat(parts, "\n  ")
end

local function check_sandbox(path)
    if config.sandbox_disabled() then
        return true
    end
    
    if not path then
        return true
    end
    
    local h = io.popen("pwd && realpath '" .. path:gsub("'", "'\\''") .. "'")
    local output = h:read("*a"):gsub("%s+$", "")
    h:close()
    
    local lines = {}
    for line in output:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    local current_dir = lines[1] or ""
    local abs_path = lines[2] or path
    
    if abs_path ~= current_dir and not abs_path:match("^" .. current_dir:gsub("/", "%%/") .. "/") then
        return false
    end
    
    return true
end

local function has_ripgrep()
    local h = io.popen("rg --version 2>/dev/null && echo yes")
    local result = h:read("*a"):gsub("%s+$", "")
    h:close()
    return result == "yes"
end

function M.execute(args)
    local text = args.text
    local path = args.path or "."
    local max_results = args.max_results or DEFAULT_MAX_RESULTS
    local context = args.context or 2
    
    if not text then
        error("Text is required")
    end
    
    -- Check sandbox
    if not check_sandbox(path) then
        local h = io.popen("pwd")
        local current_dir = h:read("*a"):gsub("%s+$", "")
        h:close()
        return {
            tool = "grep",
            friendly = ("Path: %s\n[x] Sandbox: trying to access outside current directory"):format(path),
            detailed = ("Path: %s\n[x] Sandbox: trying to access outside current directory"):format(path)
        }
    end
    
    -- Validate search text
    if not text:match("%S") then
        return {
            tool = "grep",
            friendly = "ERROR: Search text cannot be empty.",
            detailed = ("Search text \"%s\" is invalid - it cannot be empty or whitespace only."):format(text)
        }
    end
    
    -- Use ripgrep if available
    if has_ripgrep() then
        local search_path = path
        local h = io.popen("realpath '" .. path:gsub("'", "'\\''") .. "'")
        search_path = h:read("*a"):gsub("%s+$", "")
        h:close()
        
        local cmd = ("rg -n --max-count %d -C %d %q %q 2>/dev/null"):format(
            max_results, context, text, search_path
        )
        
        h = io.popen(cmd)
        local output = h:read("*a")
        h:close()
        
        local matches = {}
        for line in output:gmatch("[^\n]+") do
            if line ~= "" then
                table.insert(matches, line)
            end
        end
        
        local friendly
        if #matches == 0 then
            friendly = ("🔍 No matches found for '%s'"):format(text)
        else
            friendly = ("🔍 Found %d matches for '%s'"):format(#matches, text)
        end
        
        return {
            tool = "grep",
            friendly = friendly,
            detailed = ("Search completed: %s\n\nCommand: %s\n\nMatches:\n%s"):format(
                friendly, cmd, truncate_detailed(matches, friendly, cmd)
            )
        }
    else
        -- Fallback to grep
        local h = io.popen("realpath '" .. path:gsub("'", "'\\''") .. "'")
        local search_path = h:read("*a"):gsub("%s+$", "")
        h:close()
        
        local cmd = ("grep -rn -C %d -m %d %q %s 2>/dev/null"):format(
            context, max_results, text, search_path
        )
        
        h = io.popen(cmd)
        local output = h:read("*a")
        h:close()
        
        local matches = {}
        for line in output:gmatch("[^\n]+") do
            if line ~= "" then
                table.insert(matches, line)
            end
        end
        
        local friendly
        if #matches == 0 then
            friendly = ("🔍 No matches found for '%s'"):format(text)
        else
            friendly = ("🔍 Found %d matches for '%s'"):format(#matches, text)
        end
        
        return {
            tool = "grep",
            friendly = friendly,
            detailed = ("Search completed: %s\n\nMatches:\n%s"):format(
                friendly, truncate_detailed(matches, friendly, nil)
            )
        }
    end
end

-- Tool definition
M.TOOL_DEFINITION = {
    type = "internal",
    auto_approved = true,
    approval_excludes_arguments = false,
    description = "Searches for text in files using ripgrep (rg) or grep.",
    parameters = {
        type = "object",
        properties = {
            text = {
                type = "string",
                description = "The text pattern to search for.",
            },
            path = {
                type = "string",
                description = "The directory path to search in (default: current directory).",
                default = "."
            },
            max_results = {
                type = "integer",
                description = ("Maximum number of results to return (default: %d)."):format(DEFAULT_MAX_RESULTS),
                default = DEFAULT_MAX_RESULTS,
            },
            context = {
                type = "integer",
                description = "Number of context lines before/after match (default: 2).",
                default = 2,
            },
        },
        required = {"text"},
    },
}

M.TOOL_DEFINITION.execute = M.execute
M.TOOL_DEFINITION.formatArguments = M.format_arguments
M.TOOL_DEFINITION.validateArguments = M.validate_arguments

-- Module-level aliases for 1-1 parity with Python
M.formatArguments = M.format_arguments
M.validateArguments = M.validate_arguments

-- Aliases for 1-1 parity with Python (Python's _check_sandbox, _has_ripgrep)
M._check_sandbox = check_sandbox
M._has_ripgrep = has_ripgrep

return M
