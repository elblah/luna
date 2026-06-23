-- Edit file tool for Luna

local M = {}

local config = require("core.config")
local file_access_tracker = require("core.file_access_tracker")
local utils = require("core.utils")
local exec_utils = require("utils.exec_utils")

_plugin_system = nil

function M.set_plugin_system(ps)
    _plugin_system = ps
end

function M.record_read(path)
    file_access_tracker.record_read(path)
end

function M.was_file_read(path)
    return file_access_tracker.was_file_read(path)
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

local function read_file(path)
    local f, err = io.open(path, "r")
    if not f then
        error("Cannot read file: " .. err)
    end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f, err = io.open(path, "w")
    if not f then
        error("Cannot write file: " .. err)
    end
    f:write(content)
    f:close()
end

local function find_occurrences(content, old_string)
    if not old_string then
        return {}
    end
    
    local occurrences = {}
    local start = 1
    while true do
        local pos = content:find(old_string, start, true)
        if not pos then
            break
        end
        table.insert(occurrences, pos)
        start = pos + 1
    end
    
    return occurrences
end

function M.execute(args)
    local path = args.path
    local old_string = args.old_string
    local new_string = args.new_string or ""
    
    if not path or old_string == nil then
        error("Path and old_string are required")
    end
    
    if not check_sandbox(path) then
        error("Path: " .. path .. "\n[x] Sandbox: trying to access outside current directory")
    end
    
    -- Check if file exists
    local h = io.popen("test -f '" .. path:gsub("'", "'\\''") .. "' && echo exists")
    local exists = h:read("*a"):gsub("%s+$", "") == "exists"
    h:close()
    
    if not exists then
        error("File not found: " .. path)
    end
    
    -- Safety check: File must have been read first
    if not M.was_file_read(path) then
        return {
            tool = "edit_file",
            friendly = ("WARNING: Must read file '%s' first before editing"):format(path),
            detailed = ("Must read file first. Use read_file('%s') before editing."):format(path)
        }
    end
    
    local content = read_file(path)
    
    -- Check if old_string exists
    if not content:find(old_string, 1, true) then
        return {
            tool = "edit_file",
            friendly = ("ERROR: Text not found in '%s' - check exact match including whitespace"):format(path),
            detailed = ("old_string not found in file. Use read_file('%s') to see current content and ensure exact match."):format(path)
        }
    end
    
    -- Check for no-op edit
    if old_string == (new_string or "") then
        return {
            tool = "edit_file",
            friendly = "No changes: old_string is identical to new_string",
            detailed = "Edit would result in no changes. Provide a different new_string."
        }
    end
    
    -- Count occurrences
    local occurrences = find_occurrences(content, old_string)
    local count = #occurrences
    
    -- Replace using proper literal matching (works on Lua 5.1 and 5.3)
    local new_content = utils.replace_string(content, old_string, new_string, 1)
    
    -- Write the new content
    local wf, werr = io.open(path, "w")
    if not wf then
        error("Cannot write file: " .. tostring(werr))
    end
    wf:write(new_content)
    wf:close()
    
    -- Call plugin hook after file write
    if _plugin_system then
        _plugin_system:call_hooks("after_file_write", path, new_content)
    end
    
    -- Mark file as read since user just modified it
    M.record_read(path)
    
    local friendly
    if not new_string or new_string == "" then
        friendly = ("✓ Deleted content from '%s' (%d chars removed)"):format(path, #old_string)
    else
        friendly = ("✓ Updated '%s' (%d → %d chars)"):format(path, #old_string, #new_string)
    end
    
    local detailed = ("Path: %s\nAction: edit_file\nOld size: %d\nNew size: %d\nOccurrences: %d"):format(
        path, #old_string, #new_string, count
    )
    
    return {
        tool = "edit_file",
        friendly = friendly,
        detailed = detailed
    }
end

function M.format_arguments(args)
    local path = args.path or "(unknown)"
    local old_string = args.old_string
    local new_string = args.new_string
    
    local lines = {"Path: " .. path}
    
    if old_string ~= nil then
        local old_preview = #old_string > 50 and old_string:sub(1, 50) .. "..." or old_string
        table.insert(lines, "Old: " .. old_preview)
    end
    
    if new_string ~= nil then
        local new_preview = #new_string > 50 and new_string:sub(1, 50) .. "..." or new_string
        table.insert(lines, "New: " .. new_preview)
    end
    
    return table.concat(lines, "\n  ")
end

function M.validate_arguments(args)
    if not args.path or type(args.path) ~= "string" then
        error("edit_file requires \"path\" argument (string)")
    end
    if args.old_string == nil then
        error("edit_file requires \"old_string\" argument")
    end
end

function M.generate_preview(args)
    local path = args.path or "(unknown)"
    local old_string = args.old_string or ""
    local new_string = args.new_string or ""
    local config = require("core.config")
    local colors = config.colors
    
    -- Create temp files for diff (using isolated temp dir)
    local temp_old = exec_utils.tmpname() .. "_old.txt"
    local temp_new = exec_utils.tmpname() .. "_new.txt"
    
    local wf = io.open(temp_old, "w")
    if wf then
        wf:write(old_string)
        wf:close()
    end
    
    wf = io.open(temp_new, "w")
    if wf then
        wf:write(new_string)
        wf:close()
    end
    
    -- Check for no-op edit (old_string same as new_string)
    if old_string == new_string then
        os.remove(temp_old)
        os.remove(temp_new)
        return {
            can_approve = false,
            content = "No changes detected - old_string is identical to new_string"
        }
    end
    
    -- Generate diff
    local diff_cmd = "diff -u " .. temp_old .. " " .. temp_new .. " 2>/dev/null"
    local diff_out = io.popen(diff_cmd)
    local diff_content = diff_out and diff_out:read("*a") or ""
    if diff_out then diff_out:close() end
    
    os.remove(temp_old)
    os.remove(temp_new)
    
    -- Check if diff is empty (no changes)
    if diff_content == "" then
        return {
            can_approve = false,
            content = "No changes detected"
        }
    end
    
    -- Colorize diff (skip --- +++ headers and "No newline" footer)
    local colorized = {}
    for line in diff_content:gmatch("[^\n]+") do
        local ln = line
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
    
    local preview = "Existing file will be updated:\n\n" .. diff_content .. "\n\nPath: " .. relative_path
    
    return {
        can_approve = true,
        content = preview
    }
end

-- Tool definition
M.TOOL_DEFINITION = {
    type = "internal",
    auto_approved = false,
    approval_excludes_arguments = false,
    description = "Edit a file by replacing exact text match (old_string) with new content (new_string).",
    parameters = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "The file system path to edit.",
            },
            old_string = {
                type = "string",
                description = "The exact text to find and replace.",
            },
            new_string = {
                type = "string",
                description = "The new content to replace old_string with.",
            },
        },
        required = {"path", "old_string"},
    },
}

M.TOOL_DEFINITION.execute = M.execute
M.TOOL_DEFINITION.formatArguments = M.format_arguments
M.TOOL_DEFINITION.validateArguments = M.validate_arguments
M.TOOL_DEFINITION.generatePreview = M.generate_preview

return M
