-- Detail command implementation
-- Ported from Python commands/detail.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local config = require("core.config")
local bool_utils = require("utils.bool_utils")

local DetailCommand = setmetatable({}, BaseCommand.BaseCommand)
DetailCommand.__index = DetailCommand

function DetailCommand.new(context)
    local self = setmetatable({}, DetailCommand)
    self.context = context
    self._name = "detail"
    self._description = "Toggle detailed tool output on/off"
    return self
end

function DetailCommand:get_name()
    return self._name
end

function DetailCommand:get_description()
    return self._description
end

function DetailCommand:get_aliases()
    return {"d"}
end

function DetailCommand:execute(args)
    local enabled = config.detail_mode()
    local tty_enabled = config.detail_tty()
    local status = enabled and "ENABLED" or "DISABLED"
    local tty_status = tty_enabled and "ENABLED" or "DISABLED"

    if not args or #args == 0 then
        log.print("Detail Mode Status: " .. status)
        log.print("Detail TTY Status: " .. tty_status)
        if enabled then
            log.info("All tool parameters and results will be shown")
        else
            log.warn("Only important tool information will be shown")
        end
        if tty_enabled then
            log.info("Real-time output passthrough is ON for shell commands")
        end
        return CommandResult.new(false, false)
    end

    local action = args[1]:lower()

    if action == "tty" then
        local tty_arg = args[2]
        if not tty_arg then
            log.print("Detail TTY: " .. tty_status)
            log.info("Use 'tty on' or 'tty off' to toggle real-time output passthrough")
            return CommandResult.new(false, false)
        end
        if tty_arg == "toggle" then
            local now = not config.detail_tty()
            config.set_detail_tty(now)
            if now then
                log.success("[*] Detail TTY ENABLED")
            else
                log.warn("[*] Detail TTY DISABLED")
            end
        else
            local value = bool_utils.parse_bool(tty_arg)
            if value == nil then
                log.error("Unknown tty action: '" .. tty_arg .. "' (use on/off/toggle)")
                return CommandResult.new(false, false)
            end
            if value == config.detail_tty() then
                log.warn("[*] Detail TTY is already " .. (value and "enabled" or "disabled"))
            else
                config.set_detail_tty(value)
                if value then
                    log.success("[*] Detail TTY ENABLED")
                else
                    log.warn("[*] Detail TTY DISABLED")
                end
            end
        end
        return CommandResult.new(false, false)
    end

    if action == "toggle" then
        local now = not config.detail_mode()
        config.set_detail_mode(now)
        if now then
            log.success("[*] Detail mode ENABLED")
        else
            log.warn("[*] Detail mode DISABLED")
        end
    elseif action == "help" then
        log.print("Detail Command Usage:")
        log.print("  /detail             - Show current status")
        log.print("  /detail on          - Enable detail mode")
        log.print("  /detail off         - Disable detail mode")
        log.print("  /detail toggle      - Toggle detail mode")
        log.print("  /detail tty on      - Enable real-time shell output passthrough")
        log.print("  /detail tty off     - Disable real-time shell output passthrough")
        log.print("  /detail tty toggle  - Toggle real-time shell output passthrough")
        log.print("  /detail help        - Show this help")
        return CommandResult.new(false, false)
    else
        local value = bool_utils.parse_bool(action)
        if value == nil then
            log.error("Unknown action: " .. action .. " (use on/off/toggle/tty/help)")
            return CommandResult.new(false, false)
        end
        if value == config.detail_mode() then
            log.warn("[*] Detail mode is already " .. (value and "enabled" or "disabled"))
        else
            config.set_detail_mode(value)
            if value then
                log.success("[*] Detail mode ENABLED")
            else
                log.warn("[*] Detail mode DISABLED")
            end
        end
    end

    return CommandResult.new(false, false)
end

return DetailCommand