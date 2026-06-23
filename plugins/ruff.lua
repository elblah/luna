--[[
Ruff Plugin - Automatic Python code quality checks

Features:
- Automatic ruff check on .py file writes/edits
- User message generation when serious issues found
- Configurable via /ruff command
- Graceful fallback when ruff not installed
- Default: serious-only mode (ignores minor linting issues)
- Messages added AFTER tool results to avoid breaking conversation flow

Commands:
- /ruff - Show status
- /ruff on/off - Enable/disable
- /ruff check-serious on/off - Toggle serious-only mode
]]

local M = {}

local log = require("utils.log")
local config = require("core.config")

-- Plugin state
local _enabled = true
local _serious_only = true
local _check_args = ""
local _pending_files = {}
local _app = nil

local function get_effective_args()
    if _serious_only then
        -- Only check errors (E) and serious issues, ignore minor stuff
        return "--select E,F --ignore E501,F841,E712,F401,E722,F541"
    end
    return _check_args
end

local function which_ruff()
    local handle = io.popen("which ruff 2>/dev/null")
    if not handle then
        return false
    end
    local result = handle:read("*a")
    handle:close()
    return result and result:match("%S") ~= nil
end

local function run_ruff_check(filepath)
    if not _enabled then
        return nil
    end

    if not filepath:match("%.py$") then
        return nil
    end

    -- Check if ruff exists
    if not which_ruff() then
        return nil  -- ruff not installed, silently skip
    end

    local args = get_effective_args()
    local cmd = string.format('ruff check %s "%s"', args, filepath)

    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        return nil
    end

    local result = handle:read("*a")
    handle:close()

    if result and (result:lower():find("error") or result:lower():find("found")) then
        return string.format("Ruff issues in %s:\n%s", filepath, result)
    end
    return nil
end

local function after_file_write(path, content)
    -- Just queue the file, don't check yet
    -- This ensures tool results are added before any plugin messages
    if path and path:match("%.py$") then
        table.insert(_pending_files, path)
    end
end

local function after_tool_results(tool_results)
    -- Check all queued files
    while #_pending_files > 0 do
        local filepath = table.remove(_pending_files, 1)
        local issues = run_ruff_check(filepath)
        if issues then
            log.info("\n[ruff] " .. issues)
            -- Add message for AI to fix (this will be AFTER tool result)
            if _app and _app.message_history then
                _app.message_history:add_user_message("\n" .. issues .. "\n")
            end
        end
    end
end

local function handle_ruff_command(args)
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
        local serious_str = _serious_only and "enabled" or "disabled"
        return string.format([[Ruff Plugin Status:

- Checking: %s
- Serious-only mode: %s

Commands:
- /ruff on/off - Enable/disable checking
- /ruff check-serious on/off - Toggle serious-only mode
]], enabled_str, serious_str)
    end

    if args_str == "on" then
        _enabled = true
        return "Ruff checking enabled"
    end

    if args_str == "off" then
        _enabled = false
        return "Ruff checking disabled"
    end

    if args_str:match("^check%-serious%s+(.+)$") then
        local mode = args_str:match("^check%-serious%s+(.+)$")
        if mode == "on" then
            _serious_only = true
            return "Ruff set to serious-only mode"
        elseif mode == "off" then
            _serious_only = false
            return "Ruff set to full mode"
        end
    end

    if args_str == "check-serious" then
        local mode = _serious_only and "serious-only" or "full"
        return string.format("Ruff mode: %s (use on/off to change)", mode)
    end

    return "Unknown command. Use: /ruff [on|off|check-serious [on|off]]"
end

function M:create_plugin(ctx)
    _app = ctx.app

    -- Register hooks
    ctx:register_hook("after_file_write", after_file_write)
    ctx:register_hook("after_tool_results", after_tool_results)

    -- Register command
    ctx:register_command("/ruff", handle_ruff_command, "Ruff code quality checks")

    if config.debug() then
        log.info("[+] Ruff plugin loaded")
        log.info("    - after_file_write hook")
        log.info("    - after_tool_results hook")
        log.info("    - /ruff command")
    end

    return true
end

return M
