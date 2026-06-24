-- Debug command implementation
-- Ported from Python commands/debug.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local config = require("core.config")
local bool_utils = require("utils.bool_utils")

local DebugCommand = setmetatable({}, BaseCommand.BaseCommand)
DebugCommand.__index = DebugCommand

function DebugCommand.new(context)
    local self = setmetatable({}, DebugCommand)
    self.context = context
    self._name = "debug"
    self._description = "Toggle debug mode or show status"
    return self
end

function DebugCommand:get_name()
    return self._name
end

function DebugCommand:get_description()
    return self._description
end

function DebugCommand:get_aliases()
    return {"dbg"}
end

function DebugCommand:execute(args)
    if not args or #args == 0 then
        return self:_show_status()
    end

    local action = args[1]:lower()

    if action == "toggle" then
        local now = not config.debug()
        config.set_debug(now)
        if now then
            log.success("[*] Debug mode ENABLED")
        else
            log.warn("[*] Debug mode DISABLED")
        end
    elseif action == "verbose" then
        config.set_debug(true)
        config.set_verbose(true)
        log.success("[*] Verbose debug mode enabled")
    else
        local value = bool_utils.parse_bool(action)
        if value == nil then
            log.error("[*] Unknown debug action: " .. action .. " (use on/off/toggle)")
            return CommandResult.new(false, false)
        end
        if value == config.debug() then
            log.warn("[*] Debug mode is already " .. (value and "enabled" or "disabled"))
        else
            config.set_debug(value)
            if value then
                log.success("[*] Debug mode ENABLED")
            else
                log.warn("[*] Debug mode DISABLED")
            end
        end
    end

    return CommandResult.new(false, false)
end

function DebugCommand:_show_status()
    local debug = config.debug()

    log.print("Debug Status:")
    log.print("  Debug: " .. (debug and "ON" or "OFF"))

    if not debug then
        log.warn("Debug logging is disabled")
        log.info("Use /debug on to enable")
    end

    log.dim("\nQuick actions:")
    log.dim("  /debug on|off|toggle - Manage debug mode")
    log.dim("  /debug breakpoint|bp|break - Trigger breakpoint() for debugging")

    return CommandResult.new(false, false)
end

function DebugCommand:_enable_debug()
    if config.debug() then
        log.warn("[*] Debug mode is already enabled")
    else
        config.set_debug(true)
        log.success("[*] Debug mode ENABLED")
        log.info("Detailed output will now be shown for API calls")
    end
    return CommandResult.new(false, false)
end

function DebugCommand:_disable_debug()
    if config.debug() then
        config.set_debug(false)
        log.warn("[*] Debug mode DISABLED")
        log.info("Only essential output will be shown")
    else
        log.warn("[*] Debug mode is already disabled")
    end
    return CommandResult.new(false, false)
end

function DebugCommand:_trigger_breakpoint()
    log.warn("\n[*] Triggering breakpoint()...")
    log.info("    Use 'c' to continue, 'q' to quit, or explore variables")
    log.dim("    Type 'help' for debugger commands\n")

    -- LuaJIT doesn't have a native breakpoint, but show a stack trace snapshot
    local debugger = require("debug")
    local trace = debugger.traceback("", 2)
    log.info(trace)

    log.success("\n[*] Breakpoint snapshot shown")
    return CommandResult.new(false, false)
end

return DebugCommand
