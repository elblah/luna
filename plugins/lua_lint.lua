--[[
Lua Lint Plugin - Automatic Lua syntax checks

Features:
- Automatic syntax check on .lua file writes/edits
- User message generation when syntax errors found
- Configurable via /lua-lint command
- Graceful fallback when check fails
- Messages added AFTER tool results to avoid breaking conversation flow

Commands:
- /lua-lint - Show status
- /lua-lint on/off - Enable/disable
]]

local M = {}

local log = require("utils.log")
local config = require("core.config")

-- Plugin state
local _enabled = true
local _pending_files = {}
local _app = nil

local function check_lua_syntax(filepath)
    if not _enabled then
        return nil
    end

    if not filepath:match("%.lua$") then
        return nil
    end

    -- Use loadfile to check syntax
    local func, err = loadfile(filepath)
    if func then
        return nil  -- No errors
    end

    -- Parse error message to get line number
    local line = err:match(":(%d+):")
    local msg = err:match(":%d+: (.+)") or err

    return string.format("Lua syntax error in %s:\nLine %s: %s", filepath, line or "?", msg)
end

local function after_file_write(path, content)
    -- Just queue the file, don't check yet
    if path and path:match("%.lua$") then
        table.insert(_pending_files, path)
    end
end

local function after_tool_results(tool_results)
    -- Check all queued files
    while #_pending_files > 0 do
        local filepath = table.remove(_pending_files, 1)
        local issues = check_lua_syntax(filepath)
        if issues then
            log.info("\n[lua-lint] " .. issues)
            -- Add message for AI to fix (this will be AFTER tool result)
            if _app and _app.message_history then
                _app.message_history:add_user_message("\n" .. issues .. "\n")
            end
        end
    end
end

local function handle_lua_lint_command(args)
    local args_str
    if type(args) == "table" then
        args_str = table.concat(args, " ")
    else
        args_str = args or ""
    end
    args_str = args_str:match("^%s*(.-)%s*$") or ""

    if args_str == "" then
        -- Show status
        local enabled_str = _enabled and "enabled" or "disabled"
        return string.format([[Lua Lint Plugin Status:

- Checking: %s

Commands:
- /lua-lint on/off - Enable/disable checking
]], enabled_str)
    end

    if args_str == "on" then
        _enabled = true
        return "Lua lint checking enabled"
    end

    if args_str == "off" then
        _enabled = false
        return "Lua lint checking disabled"
    end

    return "Unknown command. Use: /lua-lint [on|off]"
end

function M:create_plugin(ctx)
    _app = ctx.app

    -- Register hooks
    ctx:register_hook("after_file_write", after_file_write)
    ctx:register_hook("after_tool_results", after_tool_results)

    -- Register command
    ctx:register_command("/lua-lint", handle_lua_lint_command, "Lua syntax checks")

    if config.debug() then
        log.info("[+] Lua lint plugin loaded")
        log.info("    - after_file_write hook")
        log.info("    - after_tool_results hook")
        log.info("    - /lua-lint command")
    end

    return true
end

return M
