-- Detail command implementation
-- Ported from Python commands/detail.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local config = require("core.config")

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
    local status = enabled and "ENABLED" or "DISABLED"
    local status_color = enabled and "green" or "yellow"

    if not args or #args == 0 then
        log.print("Detail Mode Status: " .. status)
        if enabled then
            log.info("All tool parameters and results will be shown")
        else
            log.warn("Only important tool information will be shown")
        end
        return CommandResult.new(false, false)
    end

    local action = args[1]:lower()
    if action == "on" or action == "1" or action == "enable" or action == "true" then
        if config.detail_mode() then
            log.warn("[*] Detail mode is already enabled")
        else
            config.set_detail_mode(true)
            log.success("[*] Detail mode ENABLED")
        end
    elseif action == "off" or action == "0" or action == "disable" or action == "false" then
        if config.detail_mode() then
            config.set_detail_mode(false)
            log.warn("[*] Detail mode DISABLED")
        else
            log.warn("[*] Detail mode is already disabled")
        end
    else
        log.error("Unknown action: " .. action .. " (use on/off)")
    end

    return CommandResult.new(false, false)
end

return DetailCommand