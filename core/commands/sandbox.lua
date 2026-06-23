-- Sandbox command implementation
-- Ported from Python commands/sandbox.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local config = require("core.config")

local SandboxCommand = setmetatable({}, BaseCommand.BaseCommand)
SandboxCommand.__index = SandboxCommand

function SandboxCommand.new(context)
    local self = setmetatable({}, SandboxCommand)
    self.context = context
    self._name = "sandbox-fs"
    self._description = "Show or configure filesystem sandbox status"
    return self
end

function SandboxCommand:get_name()
    return self._name
end

function SandboxCommand:get_description()
    return self._description
end

function SandboxCommand:get_aliases()
    return {"sfs"}
end

function SandboxCommand:execute(args)
    local os = require("os")
    local disabled = config.sandbox_disabled()
    local status = disabled and "DISABLED" or "ENABLED"

    if not args or #args == 0 then
        log.print("sandbox-fs Status: " .. status)
        log.print("Current directory: " .. os.getenv("PWD"))

        if disabled then
            log.warn("Sandbox-fs is DISABLED")
            log.warn("File operations can access any path on the system")
        else
            log.success("Sandbox-fs is ENABLED")
            log.success("File operations limited to current directory")
        end

        log.dim("Use /sandbox-fs on|off to toggle")
        return CommandResult.new(false, false)
    end

    local action = args[1]:lower()
    if action == "on" or action == "1" then
        if config.sandbox_disabled() then
            config.set_sandbox_disabled(false)
            log.success("Sandbox-fs is now enabled")
        else
            log.warn("Sandbox-fs is already enabled")
        end
    elseif action == "off" or action == "0" then
        if config.sandbox_disabled() then
            log.warn("Sandbox-fs is already disabled")
        else
            config.set_sandbox_disabled(true)
            log.warn("Sandbox-fs is now disabled")
            log.warn("File operations can now access any path on the system")
        end
    else
        log.error("Invalid argument. Use: /sandbox-fs [on|off]")
    end

    return CommandResult.new(false, false)
end

return SandboxCommand