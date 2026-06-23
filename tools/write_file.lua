-- Write file tool for Luna

local M = {}

local config = require("core.config")
local file_access_tracker = require("core.file_access_tracker")
local exec_utils = require("utils.exec_utils")
local path_utils = require("utils.path_utils")

_plugin_system = nil

function M.set_plugin_system(ps)
    _plugin_system = ps
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

function M.execute(args)
    local path = path_utils.expand(args.path)
    local content = args.content or ""
    
    if not path then
        error("Path is required")
    end
    
    -- Call plugin hook before file write
    if _plugin_system then
        local hook_result = _plugin_system:call_hooks("before_file_write", path, content)
        if hook_result and type(hook_result) == "string" then
            content = hook_result
        end
    end
    
    if not check_sandbox(path) then
        error("Path: " .. path .. "\n[x] Sandbox: trying to access outside current directory")
    end
    
    -- Check if file exists
    local h = io.popen("test -f '" .. path:gsub("'", "'\\''") .. "' && echo exists")
    local exists = h:read("*a"):gsub("%s+$", "") == "exists"
    h:close()
    
    -- Write file
    local f, err = io.open(path, "w")
    if not f then
        error("Cannot write file: " .. err)
    end
    f:write(content)
    f:close()
    
    -- Mark file as read since we just wrote it (like v3)
    file_access_tracker.record_read(path)
    
    -- Call plugin hook after file write
    if _plugin_system then
        _plugin_system:call_hooks("after_file_write", path, content)
    end
    
    -- Count lines
    local line_count = 0
    for _ in content:gmatch("[^\n]+") do
        line_count = line_count + 1
    end
    
    local action = exists and "Updated" or "Created"
    local friendly = ("✓ %s '%s'"):format(action, path)
    
    if not exists then
        friendly = friendly .. (" (%d lines, %d bytes)"):format(line_count, #content)
    end
    
    local detailed = ("Path: %s\nAction: %s\nSize: %d bytes\nLines: %d"):format(
        path, action, #content, line_count
    )
    
    return {
        tool = "write_file",
        friendly = friendly,
        detailed = detailed
    }
end

function M.format_arguments(args)
    local path = args.path or "(unknown)"
    local content = args.content
    
    local lines = {"Path: " .. path}
    
    if content ~= nil then
        local content_preview = #content > 50 and content:sub(1, 50) .. "..." or content
        table.insert(lines, "Content: " .. content_preview)
    end
    
    return table.concat(lines, "\n  ")
end

function M.validate_arguments(args)
    if not args.path or type(args.path) ~= "string" then
        error("write_file requires \"path\" argument (string)")
    end
end

function M.generate_preview(args)
    local path = args.path or "(unknown)"
    local content = args.content or ""
    local config = require("core.config")
    local colors = config.colors
    
    -- Check if file exists
    local handle = io.popen("test -f '" .. path:gsub("'", "'\\''") .. "' && echo exists")
    local exists = handle:read("*a"):gsub("%s+$", "") == "exists"
    handle:close()
    
    -- Create temp files for diff (using isolated temp dir)
    local temp_old = exec_utils.tmpname() .. "_old.txt"
    local temp_new = exec_utils.tmpname() .. "_new.txt"
    
    if exists then
        local f = io.open(path, "r")
        if f then
            local existing = f:read("*a")
            f:close()
            local wf = io.open(temp_old, "w")
            if wf then
                wf:write(existing)
                wf:close()
            end
        end
    else
        -- For new files, create empty old file
        local wf = io.open(temp_old, "w")
        if wf then
            wf:write("")
            wf:close()
        end
    end
    
    -- Write new content to temp
    local wf = io.open(temp_new, "w")
    if wf then
        wf:write(content)
        wf:close()
    end
    
    -- Generate diff
    local diff_cmd = "diff -u " .. temp_old .. " " .. temp_new .. " 2>/dev/null"
    local diff_out = io.popen(diff_cmd)
    local diff_content = diff_out and diff_out:read("*a") or ""
    if diff_out then diff_out:close() end
    
    -- Cleanup temp files
    os.remove(temp_old)
    os.remove(temp_new)
    
    -- Colorize diff (skip --- +++ headers and "No newline" footer like v3)
    local colorized = {}
    for line in diff_content:gmatch("[^\n]+") do
        local ln = line
        -- Skip diff header lines and "No newline" footer
        if ln:sub(1, 3) == "---" or ln:sub(1, 3) == "+++" then
            -- skip
        elseif ln:match("No newline at end of file") then
            -- skip
        elseif ln:sub(1, 1) == "-" then
            ln = colors.red .. ln .. colors.reset
            table.insert(colorized, ln)
        elseif ln:sub(1, 1) == "+" then
            ln = colors.green .. ln .. colors.reset
            table.insert(colorized, ln)
        elseif ln:sub(1, 2) == "@@" then
            ln = colors.cyan .. ln .. colors.reset
            table.insert(colorized, ln)
        else
            table.insert(colorized, ln)
        end
    end
    diff_content = table.concat(colorized, "\n")
    
    -- Get relative path
    local relative_path = path
    local pwd = io.popen("pwd")
    if pwd then
        local cwd = pwd:read("*a"):gsub("%s+$", "")
        pwd:close()
        if path:sub(1, #cwd) == cwd then
            relative_path = path:sub(#cwd + 2)
        end
    end
    
    -- Format preview like v3
    local header
    if exists then
        header = "Existing file will be updated:"
    else
        header = "New file will be created:"
    end
    
    local preview = header .. "\n\n" .. diff_content .. "\n\nPath: " .. relative_path
    
    return {
        can_approve = true,
        content = preview
    }
end

-- Tool definition
M.TOOL_DEFINITION = {
    type = "internal",
    auto_approved = false,  -- Requires approval
    approval_excludes_arguments = false,
    description = "Writes content to a file at the specified path.",
    parameters = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "The file system path to write to.",
            },
            content = {
                type = "string",
                description = "The content to write to the file.",
            },
        },
        required = {"path", "content"},
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

-- Aliases for 1-1 parity with Python (Python's _check_sandbox, file_read)
M._check_sandbox = check_sandbox
M.file_read = function(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

return M
