-- Thinking command implementation
-- Ported from Python commands/thinking.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local config = require("core.config")
local json = require("utils.json")

local ThinkingCommand = setmetatable({}, BaseCommand.BaseCommand)
ThinkingCommand.__index = ThinkingCommand

function ThinkingCommand.new(context)
    local self = setmetatable({}, ThinkingCommand)
    self.context = context
    self._name = "thinking"
    self._description = "Control thinking mode (default/on/off)"
    return self
end

function ThinkingCommand:get_name()
    return self._name
end

function ThinkingCommand:get_description()
    return self._description
end

function ThinkingCommand:execute(args)
    args = args or {}
    local current_mode = config.thinking() or "default"
    local current_effort = config.reasoning_effort()
    local current_clear = config.clear_thinking()

    if #args == 0 then
        self:_show_status(current_mode, current_effort, current_clear)
        return CommandResult.new(false, false)
    end

    local action = args[1]:lower()

    if action == "effort" then
        if #args >= 2 then
            self:_set_effort(args[2])
        else
            self:_show_effort(current_effort)
        end
        return CommandResult.new(false, false)
    end

    if action == "clear" then
        if #args >= 2 then
            self:_set_clear_thinking(args[2])
        else
            self:_show_clear_thinking(current_clear)
        end
        return CommandResult.new(false, false)
    end

    if action == "default" then
        if current_mode == "default" then
            log.warn("[*] Thinking is already set to default")
        else
            config.set_thinking("default")
            log.success("[*] Thinking set to default")
            log.info("Model will use its default thinking behavior")
        end
    elseif action == "on" or action == "1" or action == "enable" or action == "true" then
        if current_mode == "on" then
            log.warn("[*] Thinking is already enabled")
        else
            config.set_thinking("on")
            log.success("[*] Thinking ENABLED")
            log.info("Sending thinking enabled in API requests")
        end
    elseif action == "off" or action == "0" or action == "disable" or action == "false" then
        if current_mode == "off" then
            log.warn("[*] Thinking is already disabled")
        else
            config.set_thinking("off")
            log.warn("[*] Thinking DISABLED")
            log.info("Sending thinking disabled in API requests")
        end
    elseif action == "toggle" then
        if current_mode == "on" then
            config.set_thinking("off")
            log.warn("[*] Thinking DISABLED")
        elseif current_mode == "off" then
            config.set_thinking("on")
            log.success("[*] Thinking ENABLED")
        else
            config.set_thinking("on")
            log.success("[*] Thinking ENABLED")
        end
        log.info("Sending thinking updated in API requests")
    else
        self:_show_help()
    end

    return CommandResult.new(false, false)
end

function ThinkingCommand:_show_status(mode, effort, clear_thinking)
    if mode == "default" then
        log.print("Thinking: default (not controlling behavior, using API defaults)", "yellow", true)
    elseif mode == "on" then
        log.print("Thinking: on (explicitly enabled)", "green", true)
    else
        log.print("Thinking: off (explicitly disabled)", "red", true)
    end

    if effort then
        log.print("Reasoning effort: " .. effort, "green", true)
    elseif mode == "on" then
        log.info("Reasoning effort: API default (medium)")
    end

    if mode == "on" then
        if clear_thinking == nil then
            log.success("Reasoning preservation: AUTO (preserving across turns - default for coding)")
        elseif clear_thinking then
            log.info("Reasoning preservation: OFF (clearing between turns)")
        else
            log.success("Reasoning preservation: ON (preserving across turns)")
        end
    end

    if mode == "default" then
        log.info("Model will use its default thinking behavior")
    elseif mode == "on" then
        local extra = {thinking = {type = "enabled"}}
        if effort then extra.thinking.reasoning_effort = effort end
        extra.thinking.clear_thinking = (clear_thinking ~= nil) and clear_thinking or false
        log.info("Sending extra_body: " .. json.encode(extra))
    else
        log.info('Sending extra_body: {"thinking": {"type": "disabled"}}')
    end

    log.dim("Use: /thinking [default|on|off] [effort <level>] [clear <true|false>]")
end

function ThinkingCommand:_show_effort(effort)
    local valid_values = config._get_valid_reasoning_efforts()
    if effort then
        log.print("Reasoning effort: " .. effort, "green", true)
    else
        log.info("Reasoning effort: not set (API will use default)")
    end
    if valid_values then
        local sorted = {}
        for v in pairs(valid_values) do table.insert(sorted, v) end
        table.sort(sorted)
        log.info("Valid effort levels: " .. table.concat(sorted, ", "))
    end
    log.dim("Use: /thinking effort <level>")
end

function ThinkingCommand:_set_effort(value)
    local ok, err = pcall(function() config.set_reasoning_effort(value) end)
    if ok then
        log.success("[*] Reasoning effort set to: " .. value)
    else
        log.error("[*] " .. tostring(err))
    end
end

function ThinkingCommand:_show_clear_thinking(clear_thinking)
    if clear_thinking == nil then
        log.info("Reasoning preservation: AUTO (preserving across turns - default for coding)")
    elseif clear_thinking then
        log.info("Reasoning preservation: OFF (clearing between turns)")
    else
        log.success("Reasoning preservation: ON (preserving across turns)")
    end
    log.dim("Use: /thinking clear <true|false>")
end

function ThinkingCommand:_set_clear_thinking(value)
    local v = value:lower()
    if v == "true" or v == "1" or v == "yes" or v == "on" then
        config.set_clear_thinking(true)
        log.warn("[*] Clear thinking enabled (reasoning not preserved)")
        log.info("Use this for faster/cheaper simple queries")
    elseif v == "false" or v == "0" or v == "no" or v == "off" then
        config.set_clear_thinking(false)
        log.success("[*] Preserved thinking enabled")
        log.info("Reasoning will be preserved across turns (recommended for coding)")
    else
        log.error("Invalid value. Use: /thinking clear <true|false>")
    end
end

function ThinkingCommand:_show_help()
    local valid_values = config._get_valid_reasoning_efforts()

    local help_text = [[
Usage:
  /thinking [on|off|default]      Set thinking mode
  /thinking effort <level>        Set reasoning effort level
  /thinking effort                Show current effort level
  /thinking clear <true|false>    Set reasoning preservation (false=preserve, true=clear)
  /thinking clear                 Show current reasoning preservation setting
  /thinking                       Show current status
  /thinking toggle                Toggle between on/off

Examples:
  /thinking on                    Enable thinking with preserved reasoning (default for coding)
  /thinking off                   Disable thinking
  /thinking effort high           Set reasoning effort to high
  /thinking clear false           Enable preserved thinking (recommended for coding)
  /thinking clear true            Clear reasoning between turns (faster/cheaper)

Environment Variables:
  THINKING=<mode>                  Set default thinking mode (default|on|off)
  REASONING_EFFORT=<level>        Set default reasoning effort
  REASONING_EFFORT_VALID=<vals>   Comma-separated valid effort levels
  CLEAR_THINKING=<true|false>     Set reasoning preservation (false=preserve, true=clear)
]]

    if valid_values then
        local sorted = {}
        for v in pairs(valid_values) do table.insert(sorted, v) end
        table.sort(sorted)
        help_text = help_text .. "\nValid effort levels (from REASONING_EFFORT_VALID):\n  " .. table.concat(sorted, ", ") .. "\n"
    end

    log.print(help_text)
end

return ThinkingCommand
