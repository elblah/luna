-- Compact command implementation
-- Ported from Python commands/compact.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local config = require("core.config")

local CompactCommand = setmetatable({}, BaseCommand.BaseCommand)
CompactCommand.__index = CompactCommand

function CompactCommand.new(context)
    local self = setmetatable({}, CompactCommand)
    self.context = context
    self._name = "compact"
    self._description = "Compact conversation history"
    self.usage = "/compact [force <N> | stats]"
    return self
end

function CompactCommand:get_name()
    return self._name
end

function CompactCommand:get_description()
    return self._description
end

function CompactCommand:get_aliases()
    return {"c"}
end

function CompactCommand:execute(args)
    if not args then
        args = {}
    end

    local parsed = self:_parse_args(args)
    if parsed.error or parsed.help then
        return CommandResult.new(false, false)
    end

    if parsed.stats then
        return self:_show_stats()
    end

    if parsed.is_prune_operation then
        return self:_handle_prune(parsed)
    end

    self:_handle_compact(parsed)
    return CommandResult.new(false, false)
end

function CompactCommand:_show_stats()
    local message_history = self.context.message_history
    message_history:estimate_context()
    local current_tokens = self.context.stats.current_prompt_size or 0
    local threshold = config.auto_compact_threshold()
    local rounds = message_history:get_round_count()
    local percentage = 0
    if threshold > 0 then
        percentage = current_tokens / threshold * 100
    end

    log.info("Conversation Statistics:")
    log.print("  Rounds (user+assistant): " .. tostring(rounds))
    log.print("  Messages (total): " .. tostring(message_history:get_message_count()))
    log.print(string.format("  Token usage: %d / %d (%.1f%%)", current_tokens, threshold, percentage))
    log.print("  Auto-compaction: " .. (config.auto_compact_enabled() and "enabled" or "disabled"))
    log.print("  Total compactions: " .. tostring(message_history:get_compaction_count()))

    return CommandResult.new(false, false)
end

-- Parse command arguments
function CompactCommand:_parse_args(args)
    local parsed = {}
    if not args or #args == 0 then return parsed end

    local command = args[1]:lower()

    if command == "force" and #args > 1 then
        parsed.force = true
        parsed.count = tonumber(args[2]) or 1
    elseif command == "force-messages" and #args > 1 then
        parsed.force_messages = true
        parsed.count = tonumber(args[2]) or 1
    elseif command == "prune" then
        parsed.prune = (#args > 1 and args[2]:lower()) or "all"
        if parsed.prune ~= "all" and parsed.prune ~= "stats" then
            parsed.count = tonumber(parsed.prune)
            if not parsed.count then
                log.error("[X] Invalid prune count: " .. parsed.prune)
                log.error("[i] Usage: " .. self.usage)
                return {error = true}
            end
        end
        parsed.is_prune_operation = true
    elseif command == "stats" then
        parsed.stats = true
    elseif command == "highlander" then
        parsed.highlander = true
    elseif command == "hm" then
        parsed.hm = true
    elseif command == "help" then
        self:_show_help()
        return {help = true}
    else
        log.error("[X] Unknown compact command: " .. command)
        log.error("[i] Usage: " .. self.usage)
        return {error = true}
    end
    return parsed
end

-- Handle compaction operations
function CompactCommand:_handle_compact(args)
    if args.help or args.error then return end

    local message_history = self.context.message_history
    message_history:estimate_context()
    local current_tokens = self.context.stats.current_prompt_size or 0
    local threshold = config.auto_compact_threshold()
    local rounds = message_history:get_round_count()

    if args.force then
        message_history:force_compact_rounds(args.count or 1)
        return
    end

    if args.force_messages then
        message_history:force_compact_messages(args.count or 1)
        return
    end

    if args.highlander then
        local pruned = message_history:prune_old_summaries()
        if pruned > 0 then
            log.success(string.format("[+] Highlander: removed %d old [SUMMARY] message(s)", pruned))
            log.print("    Only the last [SUMMARY] remains")
        else
            log.warn("[i] Highlander: 0 or 1 [SUMMARY] messages found - nothing to prune")
        end
        return
    end

    if args.hm then
        local pruned = message_history:keep_last_message()
        if pruned > 0 then
            log.success(string.format("[+] Highlight-message: removed %d message(s), keeping only last", pruned))
        else
            log.warn("[i] Highlight-message: only 0 or 1 message(s) found - nothing to remove")
        end
        return
    end

    if not config.auto_compact_enabled() then
        log.warn("[i] Auto-compaction is disabled")
        return
    end

    if rounds == 0 then
        log.warn("[i] No messages available to compact")
        return
    end

    local percentage = 0
    if threshold > 0 then
        percentage = current_tokens / threshold * 100
    end
    if percentage < 80 then
        log.warn(string.format("[i] Auto-compaction not needed (%.1f%% of %d tokens)", percentage, threshold))
        log.warn(string.format("[i] Current conversation: %d rounds (user + assistant exchanges)", rounds))
        return
    end

    local ok, err = pcall(function() message_history:compact_memory() end)
    if not ok then
        log.error("[X] Compaction failed: " .. tostring(err))
    end
end

-- Handle prune operations
function CompactCommand:_handle_prune(args)
    local message_history = self.context.message_history
    local stats = message_history:get_tool_call_stats()

    if args.prune == "stats" then
        log.info("Tool Call Statistics:")
        log.print("  Tool results: " .. tostring(stats.count))
        log.print("  Estimated tokens: " .. tostring(stats.tokens or 0))
        log.print("  Total bytes: " .. tostring(stats.bytes or 0))
        if stats.count > 0 then
            local avg_bytes = math.floor((stats.bytes or 0) / stats.count)
            local avg_tokens = math.floor((stats.tokens or 0) / stats.count)
            log.print(string.format("  Average per result: %d bytes, %d tokens", avg_bytes, avg_tokens))
        end
        return CommandResult.new(false, false)
    end

    local prune_all = args.prune == "all"
    local prune_count = prune_all and 0 or (args.count or 1)

    if (stats.count or 0) == 0 then
        log.warn("[i] No tool results to prune")
        return CommandResult.new(false, false)
    end

    if prune_all then
        local pruned_count = message_history:prune_all_tool_results()
        log.success(string.format("[+] Pruned %d tool result(s)", pruned_count))
    else
        if prune_count < 0 then
            local keep_count = math.abs(prune_count)
            local pruned_count = message_history:prune_keep_newest_tool_results(keep_count)
            if pruned_count > 0 then
                log.success(string.format("[+] Kept %d newest tool result(s), pruned %d older result(s)", keep_count, pruned_count))
            else
                log.warn(string.format("[i] Keeping all %d tool result(s) (already <= %d)", stats.count, keep_count))
            end
        else
            local to_prune = math.min(prune_count, stats.count)
            local pruned_count = message_history:prune_oldest_tool_results(to_prune)
            log.success(string.format("[+] Pruned %d oldest tool result(s)", pruned_count))
        end
    end

    return CommandResult.new(false, false)
end

function CompactCommand:_show_help()
    log.info("Compact Command Help:")
    log.print("  " .. self.usage)
    log.print("  ")
    log.print("  Commands:")
    log.print("    /compact              Try auto-compaction")
    log.print("    /compact force <N>    Force compact N oldest rounds")
    log.print("    /compact stats        Show conversation statistics")
    log.print("    /compact help        Show this help")

    return CommandResult.new(false, false)
end

return CompactCommand
