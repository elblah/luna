-- Shell command utilities
-- Ported from Python utils/shell_utils.py

local M = {}

local ShellResult = {}
ShellResult.__index = ShellResult

function ShellResult.new(success, exit_code, stdout, stderr)
    local self = setmetatable({}, ShellResult)
    self.success = success
    self.exit_code = exit_code
    self.stdout = stdout or ""
    self.stderr = stderr or ""
    return self
end

M.ShellResult = ShellResult

function M.execute_command_sync(command, timeout_seconds)
    timeout_seconds = timeout_seconds or 30

    local handle = io.popen("timeout " .. timeout_seconds .. " bash -c " .. string.format("%q", command) .. " 2>&1")
    if not handle then
        return ShellResult.new(false, -1, "", "Failed to execute command")
    end

    local output = handle:read("*all")
    local exit_code = {handle:close()}
    exit_code = exit_code[1] or -1

    local success = (exit_code == 0)
    local stderr = ""

    -- Separate stdout and stderr if possible
    local lines = {}
    for line in output:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    return ShellResult.new(success, exit_code, output, stderr)
end

function M.execute_command_with_timeout(command, timeout_seconds)
    return M.execute_command_sync(command, timeout_seconds)
end

function M.is_executable(command)
    local handle = io.popen("command -v " .. command .. " 2>/dev/null")
    if handle then
        local result = handle:read("*all")
        handle:close()
        return result and result ~= ""
    end
    return false
end

return M
