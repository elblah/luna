-- List directory tool for Luna

local M = {}

local config = require("core.config")

local MAX_FILES = 100

function M.validate_arguments(args)
    if not args.path or args.path == "" then
        args.path = "."
    end
    if not args.max_depth or args.max_depth < 1 then
        args.max_depth = 1
    end
    if not args.type or not (args.type == "file" or args.type == "dir" or args.type == "all") then
        args.type = "all"
    end
end

function M.format_arguments(args)
    local path = args.path or "."
    local pattern = args.pattern
    local depth = args.max_depth or 1
    local list_type = args.type or "all"
    
    local parts = {}
    if path and path ~= "." then
        table.insert(parts, ("Listing directory: %s (depth %d)"):format(path, depth))
    elseif depth > 1 then
        table.insert(parts, ("Listing current dir (depth %d)"):format(depth))
    end
    
    if pattern then
        table.insert(parts, ("matching: %s"):format(pattern))
    end
    
    if list_type ~= "all" then
        table.insert(parts, ("type: %s"):format(list_type))
    end
    
    return table.concat(parts, ", ")
end

local function check_sandbox(path)
    if config.sandbox_disabled() then
        return true
    end
    
    local h = io.popen("pwd")
    local current_dir = h:read("*a"):gsub("%s+$", "")
    h:close()
    
    h = io.popen("realpath '" .. path:gsub("'", "'\\''") .. "'")
    local abs_path = h:read("*a"):gsub("%s+$", "")
    h:close()
    
    if abs_path ~= current_dir and not abs_path:match("^" .. current_dir:gsub("/", "%%/") .. "/") then
        return false
    end
    
    return true
end

function M.execute(args)
    local path = args.path or "."
    local pattern = args.pattern
    local max_depth = args.max_depth or 1
    local list_type = args.type or "all"
    
    -- Resolve path
    local h = io.popen("realpath '" .. path:gsub("'", "'\\''") .. "'")
    local resolved_path = h:read("*a"):gsub("%s+$", "")
    h:close()
    
    -- Check sandbox
    if not check_sandbox(resolved_path) then
        h = io.popen("pwd")
        local current_dir = h:read("*a"):gsub("%s+$", "")
        h:close()
        return {
            tool = "list_directory",
            friendly = ("Path: %s\n[x] Sandbox: trying to access \"%s\" outside current directory"):format(path, resolved_path),
            detailed = ("Path: %s\n[x] Sandbox: trying to access \"%s\" outside current directory"):format(path, resolved_path)
        }
    end
    
    -- Check if path exists and is a directory
    h = io.popen("test -d " .. resolved_path .. " && echo exists")
    local is_dir = h:read("*a"):gsub("%s+$", "") == "exists"
    h:close()
    
    if not is_dir then
        return {
            tool = "list_directory",
            friendly = ("Directory not found: '%s'"):format(resolved_path),
            detailed = ("Directory not found at '%s'. Path does not exist or is not a directory."):format(resolved_path)
        }
    end
    
    local ignore_dirs = config.ignore_dirs()
    local ignore_patterns = config.ignore_patterns()
    
    local files = {}
    
    -- Build ignore set for directory filtering
    local ignore_set = {}
    for _, dir in ipairs(ignore_dirs) do
        ignore_set[dir] = true
    end
    
    -- Build find command based on type filter
    local find_type = ""
    if list_type == "file" then
        find_type = " -type f"
    elseif list_type == "dir" then
        find_type = " -type d"
    end
    
    if pattern then
        -- Use find for pattern matching (files and/or directories)
        local cmd = ("find %s -maxdepth %d%s -name '%s' 2>/dev/null"):format(
            resolved_path, max_depth, find_type, pattern
        )
        h = io.popen(cmd)
        for line in h:lines() do
            local filename = line:match("([^/]+)$") or ""
            local skip = false
            for _, p in ipairs(ignore_patterns) do
                if filename:match("%" .. p .. "$") then
                    skip = true
                    break
                end
            end
            if not skip and ignore_set[filename] then
                skip = true
            end
            if not skip then
                table.insert(files, line)
                if #files >= MAX_FILES + 1 then break end
            end
        end
        h:close()
    else
        -- No pattern - use find for listing (files and/or directories)
        local cmd = ("find %s -maxdepth %d%s 2>/dev/null"):format(resolved_path, max_depth, find_type)
        h = io.popen(cmd)
        for line in h:lines() do
            -- Skip the root directory itself
            if line == resolved_path then
                -- skip
            else
                -- Filter by ignore patterns (filename only)
                local filename = line:match("([^/]+)$") or ""
                local skip = false
                for _, p in ipairs(ignore_patterns) do
                    if filename:match("%" .. p .. "$") then
                        skip = true
                        break
                    end
                end
                -- Filter by ignore dirs (entry's own name only, not parent components)
                if not skip then
                    local basename = line:match("([^/]+)$") or ""
                    if ignore_set[basename] then
                        skip = true
                    end
                end
                if not skip then
                    table.insert(files, line)
                end
            end
            if #files >= MAX_FILES + 1 then
                break
            end
        end
        h:close()
    end
    
    local actual_count = #files
    local limited = {}
    for i = 1, math.min(#files, MAX_FILES) do
        table.insert(limited, files[i])
    end
    
    if #limited == 0 then
        local msg = pattern 
            and ("No items matching '%s' in '%s'"):format(pattern, resolved_path)
            or  ("Directory is empty: '%s'"):format(resolved_path)
        return {
            tool = "list_directory",
            friendly = msg,
            detailed = msg
        }
    elseif actual_count > MAX_FILES then
        local msg = pattern
            and ("Found %d+ items matching '%s' in '%s'"):format(MAX_FILES, pattern, resolved_path)
            or  ("Found %d+ items in '%s'"):format(MAX_FILES, resolved_path)
        return {
            tool = "list_directory",
            friendly = msg,
            detailed = ("Showing first %d items:\n\n%s"):format(MAX_FILES, table.concat(limited, "\n"))
        }
    else
        local msg = pattern
            and ("✓ Found %d items matching '%s' in '%s'"):format(actual_count, pattern, resolved_path)
            or  ("✓ Found %d items in '%s'"):format(actual_count, resolved_path)
        return {
            tool = "list_directory",
            friendly = msg,
            detailed = ("Directory '%s' contents:\n\n%s"):format(resolved_path, table.concat(limited, "\n"))
        }
    end
end

-- Tool definition
M.TOOL_DEFINITION = {
    type = "internal",
    auto_approved = true,
    approval_excludes_arguments = false,
    description = "Lists files and directories in a directory, optionally matching a pattern.",
    parameters = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "The directory path to list (default: current directory).",
                default = "."
            },
            pattern = {
                type = "string",
                description = "Optional glob pattern to filter files (e.g., '*.py', '**/*.txt').",
            },
            max_depth = {
                type = "integer",
                description = "Maximum directory depth to list (default: 1 = current level only).",
                default = 1
            },
            type = {
                type = "string",
                description = "Filter by type: 'file', 'dir', or 'all' (default: all).",
                enum = {"file", "dir", "all"},
                default = "all"
            },
        },
    },
}

M.TOOL_DEFINITION.execute = M.execute
M.TOOL_DEFINITION.formatArguments = M.format_arguments
M.TOOL_DEFINITION.validateArguments = M.validate_arguments

-- Module-level aliases for 1-1 parity with Python
M.formatArguments = M.format_arguments
M.validateArguments = M.validate_arguments

-- Aliases for 1-1 parity with Python (Python's _check_sandbox, _list_recursive, etc.)
M._check_sandbox = check_sandbox
M._list_single = function(path, show_hidden)
    local cmd = "ls -1 " .. (path or ".")
    if show_hidden then cmd = "ls -1a " .. (path or ".") end
    local h = io.popen(cmd .. " 2>/dev/null")
    local items = {}
    for line in h:lines() do table.insert(items, line) end
    h:close()
    return items
end
M._list_recursive = function(path, max_depth, show_hidden)
    local cmd = ("find %s -maxdepth %d -type f"):format(path or ".", max_depth or 5)
    if not show_hidden then cmd = cmd .. " -not -path '*/\\.*'" end
    local h = io.popen(cmd .. " 2>/dev/null")
    local result = {}
    for line in h:lines() do
        table.insert(result, {name = line:match("([^/]+)$") or line, path = line, type = "file"})
    end
    h:close()
    return result
end
M._walk = function(current_path, depth, result, show_hidden)
    if not result then result = {} end
    local h = io.popen("find " .. current_path .. " -maxdepth " .. (depth or 0) .. " 2>/dev/null")
    if not h then return result end
    for line in h:lines() do
        local name = line:match("([^/]+)$") or line
        if show_hidden or not name:match("^%.") then
            table.insert(result, {name = name, path = line, type = "file"})
        end
    end
    h:close()
    return result
end

return M
