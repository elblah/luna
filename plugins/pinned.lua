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

    local function after_ai_processing(has_tool_calls)
        local messages = ctx.app.message_history:get_messages()
        if not messages or #messages == 0 then
            return
        end
        -- Get last assistant message
        for i = #messages, 1, -1 do
            local msg = messages[i]
            if msg.role == "assistant" then
                local content = msg.content
                if content and type(content) == "string" then
                    local text = content:match("^%s*(.-)%s*$")
                    if text and text ~= "" then
                        _last_text = text
                    end
                end
                break
            end
        end
    end

    local function on_before_context_bar(context)
        if not _is_enabled() then
            return
        end
        if not _last_text or _last_text == "" then
            return
        end

        local display_text = _last_text
        if #display_text > _max_len then
            display_text = display_text:sub(1, _max_len) .. "..."
        end

        -- Replace newlines with spaces for single line display
        display_text = display_text:gsub("%s+", " ")

        local c = config.colors
        if context == "user" then
            -- User path: context bar adds \n before, add \n before Pinned
            print("\n" .. c.yellow .. "Pinned: " .. display_text .. c.reset)
        else
            -- AI path: no \n from context bar, add \n after Pinned
            print(c.yellow .. "Pinned: " .. display_text .. c.reset .. "\n")
        end
    end

    local function pinned_command(args)
        if not args or args == "" then
            local status = string.format("Pinned: mode=%s, max_len=%d, enabled=%s, last_text=%d chars",
                _mode, _max_len, tostring(_is_enabled()), #_last_text)
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
            local status = string.format("Pinned: mode=%s, max_len=%d, enabled=%s, last_text=%d chars",
                _mode, _max_len, tostring(_is_enabled()), #_last_text)
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
