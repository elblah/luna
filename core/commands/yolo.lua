-- Yolo command implementation
-- Ported from Python commands/yolo.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local config = require("core.config")
local bool_utils = require("utils.bool_utils")

local YoloCommand = setmetatable({}, BaseCommand.BaseCommand)
YoloCommand.__index = YoloCommand

function YoloCommand.new(context)
    local self = setmetatable({}, YoloCommand)
    self.context = context
    self._name = "yolo"
    self._description = "Toggle YOLO mode (auto-approve tool actions)"
    return self
end

function YoloCommand:get_name()
    return self._name
end

function YoloCommand:get_description()
    return self._description
end

function YoloCommand:get_aliases()
    return {"y"}
end

function YoloCommand:execute(args)
    local enabled = config.yolo_mode()

    if not args or #args == 0 then
        -- Show status
        log.print("YOLO Mode Status: " .. (enabled and "ENABLED" or "DISABLED"))

        if enabled then
            log.success("All tool actions will be auto-approved")
            log.warn("[!] This includes run_shell_command - use with caution!")
        else
            log.error("Tool actions require explicit approval")
            log.info("Safe mode - you will be prompted before each action")
        end

        log.dim("To enable YOLO: /yolo on or export YOLO_MODE=1")
        log.dim("To disable YOLO: /yolo off")

        return CommandResult.new(false, false)
    end

    local action = args[1]:lower()
    if action == "toggle" then
        local now = not config.yolo_mode()
        config.set_yolo_mode(now)
        if now then
            log.success("YOLO mode ENABLED")
        else
            log.error("YOLO mode DISABLED")
        end
    else
        local value = bool_utils.parse_bool(action)
        if value == nil then
            log.error("Invalid argument. Use: /yolo [on|off|toggle]")
            return CommandResult.new(false, false)
        end
        if value == config.yolo_mode() then
            log.warn("YOLO mode is already " .. (value and "enabled" or "disabled"))
        else
            config.set_yolo_mode(value)
            if value then
                log.success("YOLO mode ENABLED - All tool actions will auto-approve")
                log.warn("[!] This includes potentially dangerous shell commands")
            else
                log.error("YOLO mode DISABLED - Tool actions require approval")
                log.info("Safe mode restored")
            end
        end
    end

    return CommandResult.new(false, false)
end

return YoloCommand