--[[
Plugin: mdfmt

Markdown Formatter Plugin - Format and display markdown from message history

Usage:
    /mdfmt last  - last assistant message (default)
    /mdfmt 5     - last 5 messages
    /mdfmt all   - all assistant messages
]]

local config = require("core.config")

local M = {}

function M:create_plugin(ctx)
    local function get_assistant_messages()
        local messages = ctx.app.message_history.messages
        local result = {}
        for _, m in ipairs(messages) do
            if m.role == "assistant" then
                table.insert(result, m)
            end
        end
        return result
    end

    local function get_term_width()
        local cols = os.getenv("COLUMNS")
        if cols then
            return tonumber(cols) - 4
        end
        -- Try tput
        local handle = io.popen("tput cols 2>/dev/null")
        if handle then
            local result = handle:read("*a"):match("^%s*(.-)%s*$")
            handle:close()
            if result and result ~= "" then
                return tonumber(result) - 4
            end
        end
        return 96
    end

    local function format_markdown(content)
        if not content or content == "" then
            return ""
        end

        local width = get_term_width()

        -- Try glow via temp file (Lua 5.1 io.popen limitation)
        local handle = io.popen("which glow 2>/dev/null")
        if handle then
            local glow_path = handle:read("*a"):match("^%s*(.-)%s*$")
            handle:close()
            if glow_path and glow_path ~= "" then
                local tmpfile = os.tmpname()
                local f = io.open(tmpfile, "w")
                if f then
                    f:write(content)
                    f:close()
                    local glow_cmd = string.format("glow -p -w %d '%s' 2>/dev/null", width, tmpfile)
                    local glow_handle = io.popen(glow_cmd)
                    if glow_handle then
                        local result = glow_handle:read("*a")
                        glow_handle:close()
                        os.remove(tmpfile)
                        if result and result ~= "" then
                            return result
                        end
                        return content
                    end
                    os.remove(tmpfile)
                end
            end
        end

        return content
    end

    local function extract_content(msg)
        local content = msg.content
        if type(content) == "table" then
            local parts = {}
            for _, c in ipairs(content) do
                if c.type == "text" and c.text then
                    table.insert(parts, c.text)
                end
            end
            return table.concat(parts, " ")
        end
        return content or ""
    end

    local function format_message(idx, msg)
        local content = extract_content(msg)
        if content == "" then
            return config.colors.dim .. "[Message " .. idx .. "] (empty)" .. config.colors.reset .. "\n"
        end

        local formatted = format_markdown(content)
        local header = config.colors.cyan .. "--- Message " .. idx .. " ---" .. config.colors.reset .. "\n"
        return header .. formatted .. "\n"
    end

    local function mdfmt_handler(args)
        local assistant_msgs = get_assistant_messages()

        if #assistant_msgs == 0 then
            print(config.colors.yellow .. "[*] No assistant messages in history" .. config.colors.reset)
            return
        end

        local arg = args and args[1]

        if not arg then
            -- Default: last message
            local msg = assistant_msgs[#assistant_msgs]
            local content = extract_content(msg)
            if content ~= "" then
                print(format_markdown(content))
            end
            return
        end

        arg = arg:lower()

        -- All messages
        if arg == "all" or arg == "a" then
            for i, msg in ipairs(assistant_msgs) do
                print(format_message(i, msg))
            end
            return
        end

        -- Last N messages (number)
        if arg:match("^%d+$") then
            local n = tonumber(arg)
            if n > #assistant_msgs then
                n = #assistant_msgs
            end
            if n == 1 then
                local msg = assistant_msgs[#assistant_msgs]
                local content = extract_content(msg)
                if content ~= "" then
                    print(format_markdown(content))
                end
            else
                local start_idx = #assistant_msgs - n + 1
                for i = start_idx, #assistant_msgs do
                    print(format_message(i, assistant_msgs[i]))
                end
            end
            return
        end

        -- Last message explicitly
        if arg == "last" or arg == "l" then
            local msg = assistant_msgs[#assistant_msgs]
            local content = extract_content(msg)
            if content ~= "" then
                print(format_markdown(content))
            end
            return
        end

        print(config.colors.yellow .. "[*] Unknown argument: " .. arg .. config.colors.reset)
        print(config.colors.dim .. "    Usage: /mdfmt [last|n|all]" .. config.colors.reset)
        print(config.colors.dim .. "      /mdfmt      - last message" .. config.colors.reset)
        print(config.colors.dim .. "      /mdfmt last - last message" .. config.colors.reset)
        print(config.colors.dim .. "      /mdfmt 5    - last 5 messages" .. config.colors.reset)
        print(config.colors.dim .. "      /mdfmt all  - all messages" .. config.colors.reset)
    end

    ctx:register_command("mdfmt", mdfmt_handler, "Format markdown in message history")
end

return M
