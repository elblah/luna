-- Stats command implementation
-- Ported from Python commands/stats.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")

local StatsCommand = setmetatable({}, BaseCommand.BaseCommand)
StatsCommand.__index = StatsCommand

function StatsCommand.new(context)
    local self = setmetatable({}, StatsCommand)
    self.context = context
    self._name = "stats"
    self._description = "Show session statistics"
    return self
end

function StatsCommand:get_name()
    return self._name
end

function StatsCommand:get_description()
    return self._description
end

function StatsCommand:execute(args)
    local s = self.context.stats
    log.print("=== Session Statistics ===")
    log.print("API Requests: " .. tostring(s.api_requests or 0))
    log.print("  Success: " .. tostring(s.api_success or 0))
    log.print("  Errors: " .. tostring(s.api_errors or 0))
    log.print("Messages Sent: " .. tostring(s.messages_sent or 0))
    log.print("Tokens: " .. tostring(s.tokens_processed or 0))
    log.print("  Prompt: " .. tostring(s.prompt_tokens or 0))
    log.print("  Completion: " .. tostring(s.completion_tokens or 0))
    log.print("Compactions: " .. tostring(s.compactions or 0))
    return CommandResult.new(false, false)
end

return StatsCommand
