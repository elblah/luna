-- compact_strategy.lua - Token-aware compaction strategy plugin
--
-- Triggers compaction when context reaches threshold, but preserves
-- configurable amount of context instead of brutal full compaction.
--
-- Env vars:
--   COMPACT_STRATEGY_THRESHOLD     - Trigger compaction at X% of context size (default: disabled)
--   COMPACT_STRATEGY_KEEP_MESSAGES - Keep N newest messages (mutually exclusive with KEEP_PERCENT)
--   COMPACT_STRATEGY_KEEP_PERCENT  - Keep N% of tokens from newest messages (mutually exclusive)
--
-- Example:
--   COMPACT_STRATEGY_THRESHOLD=50 COMPACT_STRATEGY_KEEP_MESSAGES=30 lua main.lua
--   # When context > 50%, compact but keep 30 newest messages
--
--   COMPACT_STRATEGY_THRESHOLD=50 COMPACT_STRATEGY_KEEP_PERCENT=20 lua main.lua
--   # When context > 50%, compact but keep 20% of current tokens

local M = {}

local log = require("utils.log")
local config = require("core.config")
local token_estimator = require("core.token_estimator")

-- Track last compaction size to avoid re-triggering
local _last_compact_size = 0
local _threshold_pct = 0

function M.create_plugin(ctx)
    -- Read configuration
    local threshold_str = os.getenv("COMPACT_STRATEGY_THRESHOLD") or "0"
    _threshold_pct = tonumber(threshold_str) or 0
    local keep_messages = os.getenv("COMPACT_STRATEGY_KEEP_MESSAGES")
    local keep_percent = os.getenv("COMPACT_STRATEGY_KEEP_PERCENT")
    
    -- Handle empty env vars (empty string is truthy in Lua)
    if keep_messages == "" then keep_messages = nil end
    if keep_percent == "" then keep_percent = nil end

    if _threshold_pct <= 0 then
        return {}
    end

    if keep_messages and keep_percent then
        log.error("[!] compact_strategy: KEEP_MESSAGES and KEEP_PERCENT are mutually exclusive")
        return {}
    end

    local function get_colors()
        return config.colors or {}
    end

    -- Hook: Update threshold when context size changes via /cs
    local function on_context_size_changed(new_size)
        _last_compact_size = 0  -- Reset to allow re-trigger at new threshold
        local c = get_colors()
        local threshold_tokens = math.floor(new_size * (_threshold_pct / 100))
        log.warn("[compact_strategy] Context size changed to " .. new_size .. ", threshold now " .. threshold_tokens .. " tokens")
    end

    -- Hook: Trigger compaction when threshold reached
    local function on_after_ai_processing(has_tool_calls)
        local stats = ctx.app.stats
        local current_tokens = stats.current_prompt_size or 0
        local max_tokens = config.context_size()

        if current_tokens == 0 then
            return
        end

        -- Check if threshold reached
        local threshold_tokens = math.floor(max_tokens * (_threshold_pct / 100))
        if current_tokens < threshold_tokens then
            return
        end

        -- Avoid re-triggering (only compact once per growth cycle)
        if current_tokens <= _last_compact_size then
            return
        end

        _last_compact_size = current_tokens

        local c = get_colors()
        local pct = math.floor(100 * current_tokens / max_tokens)

        -- Calculate how many messages to keep
        if keep_messages then
            local n = -tonumber(keep_messages)
            local msg_count = ctx.app.message_history:get_message_count()
            local compact_count = math.max(0, msg_count - tonumber(keep_messages))
            log.warn("[compact_strategy] Context " .. current_tokens .. "/" .. max_tokens .. " (" .. pct .. "%) - keeping " .. keep_messages .. " msgs, compacting " .. compact_count)
            ctx.app.message_history:force_compact_messages(n)
        elseif keep_percent then
            local target_tokens = math.floor(max_tokens * tonumber(keep_percent) / 100)
            local messages = ctx.app.message_history.messages

            -- Iterate from newest backwards, sum cached tokens
            local kept = 0
            local count = 0
            for i = #messages, 1, -1 do
                local msg = messages[i]
                if msg.role == "system" then
                    -- Skip system message but count it as kept
                    count = count + 1
                else
                    -- Use cached token count
                    local tokens = token_estimator.count_message_tokens(msg)
                    if kept + tokens > target_tokens then
                        break
                    end
                    kept = kept + tokens
                    count = count + 1
                end
            end

            local n = -count
            log.warn("[compact_strategy] Context " .. current_tokens .. "/" .. max_tokens .. " (" .. pct .. "%) - keeping " .. keep_percent .. "% (" .. target_tokens .. " tokens, ~" .. count .. " msgs)")
            ctx.app.message_history:force_compact_messages(n)
        else
            log.warn("[!] compact_strategy: No KEEP_MESSAGES or KEEP_PERCENT set")
            return
        end
    end

    -- Register hooks
    ctx:register_hook("after_ai_processing", on_after_ai_processing)
    ctx:register_hook("on_context_size_changed", on_context_size_changed)

    if config.debug() then
        log.debug("[+] compact_strategy plugin loaded")
        log.debug("  - Threshold: " .. _threshold_pct .. "% of " .. config.context_size() .. " tokens")
        if keep_messages then
            log.debug("  - Keep messages: " .. keep_messages)
        elseif keep_percent then
            log.debug("  - Keep percent: " .. keep_percent .. "%")
        end
    end

    return {}
end

return M.create_plugin
