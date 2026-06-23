-- Retry command implementation
-- Ported from Python commands/retry.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local config = require("core.config")

local RetryCommand = setmetatable({}, BaseCommand.BaseCommand)
RetryCommand.__index = RetryCommand

function RetryCommand.new(context)
    local self = setmetatable({}, RetryCommand)
    self.context = context
    self._name = "retry"
    self._description = "Retry the last message or configure retry limit"
    return self
end

function RetryCommand:get_name()
    return self._name
end

function RetryCommand:get_description()
    return self._description
end

function RetryCommand:get_aliases()
    return {"r"}
end

function RetryCommand:execute(args)
    if not args then
        args = {}
    end

    -- Handle /retry help
    if args[1] and args[1]:lower() == "help" then
        self:show_help()
        return CommandResult.new(false, false)
    end

    -- Handle /retry limit [n]
    if args[1] and args[1]:lower() == "limit" then
        if args[2] then
            self:handle_limit(args[2])
        else
            self:show_current_limit()
        end
        return CommandResult.new(false, false)
    end

    -- Handle /retry max_backoff [n]
    if args[1] and args[1]:lower() == "max_backoff" then
        if args[2] then
            self:handle_max_backoff(args[2])
        else
            self:show_current_max_backoff()
        end
        return CommandResult.new(false, false)
    end

    -- Default: retry last request
    local messages = self.context.message_history:get_messages()
    local has_user_message = false
    for _, msg in ipairs(messages) do
        if msg.role == "user" then
            has_user_message = true
            break
        end
    end

    if not has_user_message then
        log.error("[*] Cannot retry: No user messages found")
        return CommandResult.new(false, false)
    end

    log.print("[*] Retrying last request...")
    return CommandResult.new(false, true)
end

function RetryCommand:handle_limit(value)
    local num_value = tonumber(value)
    if not num_value or num_value < 0 then
        log.error("[*] Invalid number. Use: /retry limit <number> (0 = unlimited)")
        return
    end

    config.set_runtime_max_retries(num_value)
    local display = num_value == 0 and "UNLIMITED" or tostring(num_value)
    log.print("[*] Max retries set to: " .. display)
end

function RetryCommand:show_current_limit()
    local current = config.effective_max_retries()
    local display = current == 0 and "UNLIMITED" or tostring(current)
    log.print("[*] Current retry limit: " .. display)
end

function RetryCommand:handle_max_backoff(value)
    local num_value = tonumber(value)
    if not num_value or num_value < 1 then
        log.error("[*] Invalid number. Use: /retry max_backoff <seconds> (minimum: 1)")
        return
    end

    config.set_runtime_max_backoff(num_value)
    log.print("[*] Max backoff set to: " .. tostring(num_value) .. "s")
end

function RetryCommand:show_current_max_backoff()
    local current = config.effective_max_backoff()
    log.print("[*] Current max backoff: " .. tostring(current) .. "s")
end

function RetryCommand:show_help()
    local current_limit = config.effective_max_retries()
    local current_backoff = config.effective_max_backoff()
    local limit_display = current_limit == 0 and "UNLIMITED" or tostring(current_limit)

    local help_text = [[Usage:
  /retry              Retry the last message
  /retry limit        Show current retry limit
  /retry limit <n>    Set retry limit (0 = unlimited)
  /retry max_backoff        Show current max backoff
  /retry max_backoff <n>    Set max backoff in seconds
  /retry help         Show this help message

Current Settings:
  Max retries: ]] .. limit_display .. [[
  Max backoff: ]] .. tostring(current_backoff) .. [[s

Examples:
  /retry              Retry last message
  /retry limit        Show current limit
  /retry limit 3      Set max retries to 3
  /retry limit 0      Unlimited retries
  /retry max_backoff  Show current max backoff
  /retry max_backoff 120 Set max backoff to 120s

The retry limit controls how many times AI Coder will retry failed API calls.
Exponential backoff is used: 2s, 4s, 8s, 16s, 32s, max_backoff between retries.

Environment Variables:
  MAX_RETRIES=<n>         Set default retry limit (default: 10)
  MAX_BACKOFF_SECONDS=<n> Set default max backoff in seconds (default: 64)]]

    log.print(help_text)
end

return RetryCommand
