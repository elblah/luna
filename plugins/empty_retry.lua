--[[
Empty Retry Plugin - Detects empty AI responses and retries with a nudge
--]]

local M = {}

local log = require("utils.log")
local config = require("core.config")

-- Service state
local _enabled = true
local _delay_seconds = 10
local _retry_count = 0
local _custom_message = nil
local _env_message = nil
local _app = nil

local _default_message = [[Your previous response was empty. This is unusual. Before continuing, reflect:
- Are you overthinking, rate-limited, context-overflowed, output-timing-out, or writing too much?
- If context is long, summarize first.
- If planning too much, act immediately on one small step.
- If your response was getting long, split it into shorter pieces.
- Keep the session goal in mind.
Output even a small action now, then continue step by step until the goal is achieved.]]

local function is_enabled()
    return _enabled
end

local function set_enabled(enabled)
    _enabled = enabled
    if not enabled then
        _retry_count = 0
    end
end

local function get_delay()
    return _delay_seconds
end

local function set_delay(seconds)
    _delay_seconds = math.max(1, seconds)
end

local function get_retry_count()
    return _retry_count
end

local function increment_retry()
    _retry_count = _retry_count + 1
end

local function reset_retry()
    _retry_count = 0
end

local function get_message()
    if _custom_message then
        return _custom_message
    end
    if _env_message then
        return _env_message
    end
    return _default_message
end

local function get_message_source()
    if _custom_message then
        return "user override"
    end
    if _env_message then
        return "env var (AICODER_EMPTY_RETRY_MESSAGE)"
    end
    return "default"
end

-- Command handlers
local function handle_r(args)
    increment_retry()
    local delay = get_delay()
    log.warn("[EMPTY-RETRY] Manual retry triggered... retrying in " .. delay .. "s")
    
    -- Sleep is blocking - use os.execute workaround
    os.execute("sleep " .. delay)
    
    return get_message()
end

local function handle_empty_retry(args)
    local cmd = args and args:match("^%s*(.-)%s*$") or ""
    
    if cmd == "" or cmd == "help" then
        return [[Empty Retry Plugin - Auto-retry on empty AI responses

Usage:
  /r                    Trigger retry manually
  /empty-retry on       Enable auto-retry
  /empty-retry off      Disable auto-retry
  /empty-retry delay N  Set delay in seconds (default: 10)
  /empty-retry status   Show current settings
  /empty-retry message              Show current retry message
  /empty-retry message "text..."    Set custom retry message
  /empty-retry message --clear      Clear custom message]]
    end
    
    if cmd == "on" then
        set_enabled(true)
        return "Empty retry enabled."
    end
    
    if cmd == "off" then
        set_enabled(false)
        return "Empty retry disabled."
    end
    
    if cmd:match("^delay%s+%d+$") then
        local seconds = tonumber(cmd:match("^delay%s+(%d+)$"))
        set_delay(seconds)
        return "Empty retry delay set to " .. seconds .. " seconds."
    end
    
    if cmd == "status" then
        local status = is_enabled() and "enabled" or "disabled"
        local delay = get_delay()
        local count = get_retry_count()
        return "Empty retry: " .. status .. ", delay: " .. delay .. "s, retries so far: " .. count
    end
    
    if cmd:match("^message%s+") then
        local message_text = cmd:match("^message%s+(.+)$")
        if not message_text or message_text == "" then
            local msg = get_message()
            local source = get_message_source()
            return "Current message: \"" .. msg .. "\"\nSource: " .. source
        end
        if message_text == "--clear" then
            _custom_message = nil
            local source = get_message_source()
            return "Custom message cleared. Using: " .. source
        end
        _custom_message = message_text
        return "Retry message set to: \"" .. message_text .. "\""
    end
    
    return "Unknown command: " .. cmd .. ". Use 'on', 'off', 'delay N', 'message', or 'status'."
end

-- Hook handler for after_ai_processing
local function handle_after_ai_processing()
    if not is_enabled() then
        return nil
    end
    
    if not _app or not _app.message_history then
        return nil
    end
    
    -- Check last assistant message
    local messages = _app.message_history:get_messages()
    local last_content = ""
    
    for i = #messages, 1, -1 do
        local msg = messages[i]
        if msg.role == "assistant" then
            if type(msg.content) == "string" then
                last_content = msg.content
            elseif type(msg.content) == "table" then
                for _, v in ipairs(msg.content) do
                    if v.type == "text" then
                        last_content = v.text or ""
                        break
                    end
                end
            end
            break
        end
    end
    
    -- If there's actual content, not empty - reset counter
    if last_content and last_content:match("%S") then
        reset_retry()
        return nil
    end
    
    -- Check if AI made tool calls or has reasoning - if so, NOT empty
    local messages = _app.message_history:get_messages()
    for i = #messages, 1, -1 do
        local msg = messages[i]
        if msg.role == "assistant" then
            -- Check tool_calls field (where Luna stores tool calls)
            if msg.tool_calls and #msg.tool_calls > 0 then
                -- AI made tool calls, not empty
                reset_retry()
                return nil
            end
            -- Check reasoning fields (thinking, reasoning_content, reasoning)
            for _, field in ipairs({"thinking", "reasoning_content", "reasoning"}) do
                if msg[field] and msg[field] ~= "" then
                    -- AI has reasoning, not empty
                    reset_retry()
                    return nil
                end
            end
            break
        end
    end
    
    -- Empty response detected - retry
    increment_retry()
    local delay = get_delay()
    local count = get_retry_count()
    
    log.warn("[EMPTY-RETRY] Empty message detected (retry #" .. count .. ")... retrying in " .. delay .. "s")
    
    -- Blocking sleep
    os.execute("sleep " .. delay)
    
    return get_message()
end

function M:create_plugin(ctx)
    _app = ctx.app
    
    -- Check env var
    local env_msg = os.getenv("AICODER_EMPTY_RETRY_MESSAGE")
    if env_msg then
        _env_message = env_msg
        if config.debug() then
            print("    - Env var message loaded: \"" .. env_msg .. "\"")
        end
    end
    
    -- Register commands
    ctx:register_command("/r", handle_r, "Retry the last message (manual trigger)")
    ctx:register_command("/empty-retry", handle_empty_retry, "Configure empty response auto-retry")
    
    -- Register hook
    ctx:register_hook("after_ai_processing", handle_after_ai_processing)
    
    if config.debug() then
        print("[+] Empty retry plugin loaded")
        print("    - /r command (manual retry)")
        print("    - /empty-retry command (settings)")
    end
    
    return true
end

return M
