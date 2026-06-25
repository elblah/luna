-- Pinned Plugin - Show last AI text message above context bar
-- Solves the problem of tool output flooding making it hard to follow
-- what the AI said last.
--
-- Commands:
--   /pinned default  - Auto mode (on when details on, off when details off)
--   /pinned on       - Always show
--   /pinned off      - Never show
--   /pinned len <n>  - Set max characters (default: 300)
--   /pinned status   - Show current settings

local config = require("core.config")
local log = require("utils.log")

local M = {}

function M:create_plugin(ctx)
    local _mode = "default"  -- "default", "on", "off"
    local _max_len = 300
    local _last_text = ""
    local _last_reasoning = ""

    local function _is_enabled()
        if _mode == "on" then
            return true
        end
        if _mode == "off" then
            return false
        end
        -- default: on when detail mode is on
        return config.detail_mode()
    end

    local function _get_msg_reasoning(msg)
        -- Build field list: env var override first, then guessed fields
        local fields = {"reasoning_content", "reasoning", "thinking", "reasoning_text"}
        local override = config.get_reasoning_field()
        if override then
            table.insert(fields, 1, override)
        end
        for _, field in ipairs(fields) do
            local val = msg[field]
            if val and type(val) == "string" then
                local trimmed = val:match("^%s*(.-)%s*$")
                if trimmed and trimmed ~= "" then
                    return trimmed
                end
            end
        end
        return ""
    end

    local function after_ai_processing(has_tool_calls)
        local messages = ctx.app.message_history:get_messages()
        if not messages or #messages == 0 then
            return
        end
        -- Get last assistant message
        for i = #messages, 1, -1 do
            local msg = messages[i]
            if msg.role == "assistant" then
                -- Capture reasoning if present (check all provider field names)
                local reasoning = _get_msg_reasoning(msg)
                if reasoning ~= "" then
                    _last_reasoning = reasoning
                end
                -- Capture text content
                local content = msg.content
                if content and type(content) == "string" then
                    local text = content:match("^%s*(.-)%s*$")
                    if text and text ~= "" then
                        _last_text = text
                    end
                    -- else: no text, keep old _last_text as reminder
                end
                -- else: non-string content, keep old _last_text as reminder
                break
            end
        end
    end

    -- Heuristic: prefer reasoning if concise (fits _max_len), else text.
    local function _get_display_text()
        -- Try reasoning if it fits
        if _last_reasoning ~= "" and #_last_reasoning <= _max_len then
            return _last_reasoning
        end
        -- Fall back to last text
        if _last_text ~= "" then
            return _last_text
        end
        return nil
    end

    local function on_before_context_bar(context)
        if not _is_enabled() then
            return
        end
        -- User context means new interaction: clear pinned state
        if context ~= "ai" then
            _last_text = ""
            _last_reasoning = ""
            return
        end
        local display_text = _get_display_text()
        if not display_text then
            return
        end

        if #display_text > _max_len then
            display_text = display_text:sub(1, _max_len) .. "..."
        end

        -- Replace newlines with spaces for single line display
        display_text = display_text:gsub("%s+", " ")

        local c = config.colors
        -- AI path: no \n from context bar, add \n after Pinned
        print(c.yellow .. "Pinned: " .. display_text .. c.reset .. "\n")
    end

    local function pinned_command(args)
        if not args or args == "" then
            local status = string.format("Pinned: mode=%s, max_len=%d, enabled=%s, text=%d chars, reasoning=%d chars",
                _mode, _max_len, tostring(_is_enabled()), #_last_text, #_last_reasoning)
            print(status)
            return
        end

        local parts = {}
        for part in args:gmatch("%S+") do
            table.insert(parts, part)
        end
        local cmd = parts[1]:lower()

        if cmd == "default" then
            _mode = "default"
            print("Pinned mode: default (auto)")
        elseif cmd == "on" then
            _mode = "on"
            print("Pinned mode: on (always)")
        elseif cmd == "off" then
            _mode = "off"
            print("Pinned mode: off (never)")
        elseif cmd == "len" then
            if #parts < 2 then
                print("Current max length: " .. _max_len .. " chars")
                return
            end
            local new_len = tonumber(parts[2])
            if not new_len then
                print("Invalid number. Usage: /pinned len <number>")
                return
            end
            if new_len < 10 then
                print("Length must be at least 10")
                return
            end
            if new_len > 2000 then
                print("Length must be at most 2000")
                return
            end
            _max_len = new_len
            print("Max length set to " .. _max_len .. " chars")
        elseif cmd == "status" then
            local status = string.format("Pinned: mode=%s, max_len=%d, enabled=%s, text=%d chars, reasoning=%d chars",
                _mode, _max_len, tostring(_is_enabled()), #_last_text, #_last_reasoning)
            print(status)
        else
            print("Usage: /pinned [default|on|off|len <n>|status]")
        end
    end

    -- Register hooks
    ctx:register_hook("after_ai_processing", after_ai_processing)
    ctx:register_hook("on_before_context_bar", on_before_context_bar)

    -- Register command
    ctx:register_command("pinned", pinned_command, "Show/controls pinned message display")

    if config.debug() then
        log.debug("  - after_ai_processing hook (pinned)")
        log.debug("  - on_before_context_bar hook (pinned)")
    end
end

return M
