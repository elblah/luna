-- Run shell command tool for Luna

local M = {}

local config = require("core.config")
local exec = require("utils.exec_utils")

local DEFAULT_TIMEOUT = 30

function M.execute(args)
    local command = args.command
    local timeout = args.timeout or DEFAULT_TIMEOUT
    local cwd = args.cwd
    
    if not command then
        error("Command is required")
    end
    
    local result = exec.exec(command, timeout, cwd)
    
    local friendly
    if result.exit_code == 0 then
        friendly = ("✓ Command completed (exit code: %d)"):format(result.exit_code)
    elseif result.exit_code == 124 then
        friendly = ("✗ Command timed out after %ds"):format(timeout)
    else
        friendly = ("✗ Command failed (exit code: %d)"):format(result.exit_code)
    end
    
    local detailed
    if result.exit_code == 124 then
        detailed = ("COMMAND TIMED OUT after %d seconds\n\nCommand: %s\nExit code: %d\nWorking directory: %s\n\nOutput:\n%s\n\nGUIDANCE: If this task needs to complete, use a longer timeout."):format(
            timeout, command, result.exit_code, cwd or ".", result.stdout or "(no output)"
        )
    else
        detailed = ("Command: %s\nExit code: %d\nTimeout: %ds\nWorking directory: %s\n\nOutput:\n%s"):format(
            command, result.exit_code, timeout, cwd or ".", result.stdout or ""
        )
    end
    
    return {
        tool = "run_shell_command",
        friendly = friendly,
        detailed = detailed
    }
end

function M.format_arguments(args)
    local command = args.command or "(unknown)"
    local timeout = args.timeout or DEFAULT_TIMEOUT
    
    local lines = {}
    if command then
        table.insert(lines, "Command: " .. command)
    end
    
    if timeout ~= DEFAULT_TIMEOUT then
        table.insert(lines, "Timeout: " .. timeout .. "s")
    end
    
    return table.concat(lines, "\n")
end

function M.validate_arguments(args)
    if not args.command or type(args.command) ~= "string" then
        error("run_shell_command requires \"command\" argument (string)")
    end
end

-- Tool definition
M.TOOL_DEFINITION = {
    type = "internal",
    auto_approved = false,
    approval_excludes_arguments = false,
    description = "Executes a shell command and returns the output.",
    parameters = {
        type = "object",
        properties = {
            command = {
                type = "string",
                description = "The shell command to execute.",
            },
            timeout = {
                type = "integer",
                description = ("Maximum execution time in seconds (default: %d)."):format(DEFAULT_TIMEOUT),
                default = DEFAULT_TIMEOUT,
            },
            cwd = {
                type = "string",
                description = "Optional working directory for command execution.",
            },
        },
        required = {"command"},
    },
}

M.TOOL_DEFINITION.execute = M.execute
M.TOOL_DEFINITION.formatArguments = M.format_arguments
M.TOOL_DEFINITION.validateArguments = M.validate_arguments

-- Module-level aliases
M.formatArguments = M.format_arguments
M.validateArguments = M.validate_arguments

return M
