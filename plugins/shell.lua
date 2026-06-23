-- Shell Plugin - Execute shell commands
-- Features:
-- - Direct command execution via /shell command
-- - Useful for checking current directory (pwd), file operations, etc.

local M = {}

local log = require("utils.log")
local config = require("core.config")

local DEFAULT_TIMEOUT = 600  -- 10 minutes

function M.execute_shell(command, timeout, cwd)
    if not command or not command:match("%S") then
        return "Error: Command cannot be empty"
    end

    timeout = timeout or DEFAULT_TIMEOUT
    cwd = cwd or nil  -- nil uses current directory

    local cmd
    if cwd then
        cmd = string.format("cd %s && %s", string.format("%q", cwd), command)
    else
        cmd = command
    end

    local handle = io.popen("timeout " .. timeout .. " bash -c " .. string.format("%q", cmd) .. " 2>&1")
    if not handle then
        return "Error: Failed to execute command"
    end

    local output = handle:read("*all")
    handle:close()

    return output
end

function M.handle_shell_command(args)
    -- args can be table (from command_handler) or string
    local args_str
    if type(args) == "table" then
        args_str = table.concat(args, " ")
    else
        args_str = args or ""
    end

    if not args_str or not args_str:match("%S") then
        print([[Shell Plugin

Execute shell commands directly.

Usage:
    /shell <command>

Examples:
    /shell pwd              - Show current working directory
    /shell ls -la           - List files in current directory
    /shell cp file.txt /mnt/ - Copy file to /mnt/
    /shell whoami           - Show current user
    /shell date             - Show current date/time

Note: Commands have a 10-minute timeout.
]])
        return
    end

    local result = M.execute_shell(args_str:match("^%s*(.*%S)") or "")
    print(result)
end

function M.create_plugin(ctx)
    log.debug("[shell] Plugin loaded!")

    ctx:register_command("/shell", M.handle_shell_command, "Execute shell commands")
    ctx:register_command("!", M.handle_shell_command, "Shorthand for /shell")

    if config.debug() then
        log.debug("  - /shell command")
    end

    return M
end

return M.create_plugin
