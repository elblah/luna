--[[
Lua Runtime Plugin - Execute Lua code inside Luna's process for debugging
WARNING: This gives AI direct access to Luna's internal runtime. Disabled by default.
--]]

local M = {}
local log = require("utils.log")

-- State
local _state = {
    enabled = false,
    ctx = nil,
}

-- Capture print output during execution
local capture_buffer = {}

local function capture_print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    table.insert(capture_buffer, table.concat(parts, "\t"))
end

-- Tool handler
local function run_inline_lua(args)
    local code = (args.code or ""):match("^%s*(.-)%s*$")
    if not code or code == "" then
        return {
            tool = "run_inline_lua",
            friendly = "Error: Code cannot be empty",
            detailed = "Code cannot be empty"
        }
    end

    -- Clear capture buffer
    capture_buffer = {}

    -- Full environment via __index = _G (debugging tool, user-approved)
    local exec_env = setmetatable({
        print = capture_print,
        ctx = _state.ctx,
        app = _state.ctx.app,
        log = log,
    }, {__index = _G})

    -- Compile
    local func, compile_err = load(code, "=run_inline_lua", "t", exec_env)
    if not func then
        return {
            tool = "run_inline_lua",
            friendly = "Error: " .. compile_err,
            detailed = "Compile error: " .. compile_err
        }
    end

    -- Execute
    local ok, result = pcall(func)
    if not ok then
        return {
            tool = "run_inline_lua",
            friendly = "Error: " .. tostring(result),
            detailed = "Runtime error: " .. tostring(result)
        }
    end

    -- Build output
    local lines = {}
    if result ~= nil then
        table.insert(lines, "return: " .. tostring(result))
    end
    for _, l in ipairs(capture_buffer) do
        table.insert(lines, l)
    end
    if #lines == 0 then
        table.insert(lines, "[code executed successfully, no output]")
    end

    return {
        tool = "run_inline_lua",
        friendly = "Code executed successfully",
        detailed = "Code:\n" .. code .. "\n\nOutput:\n" .. table.concat(lines, "\n")
    }
end

local function format_arguments(args)
    local code = args.code or ""
    local nlines = 0
    for _ in code:gmatch("[^\n]+") do nlines = nlines + 1 end
    local status = _state.enabled and "ENABLED" or "DISABLED"
    local preview = code:len() > 60 and code:sub(1, 57) .. "..." or code
    preview = preview:gsub("\n", "\\n")
    return string.format("[%s] run_inline_lua: %d lines | %s", status, nlines, preview)
end

local function generate_preview(args)
    local code = args.code or ""
    local nlines = 0
    for _ in code:gmatch("[^\n]+") do nlines = nlines + 1 end
    local status = _state.enabled and "ENABLED" or "DISABLED"

    if not _state.enabled then
        return {
            tool = "run_inline_lua",
            content = string.format(
                "Runtime Lua: %s\n\nWARNING: DISABLED - execution blocked\nEnable with: /lua-runtime on\n\nCode (%d lines):\n%s",
                status, nlines, code
            ),
            can_approve = false
        }
    end

    return {
        tool = "run_inline_lua",
        content = string.format(
            "Runtime Lua: %s\n\nAvailable:\n  app  - AICoder instance\n  ctx  - PluginContext\n  log  - Logger\n  os/io - system access\n\nCode (%d lines):\n%s",
            status, nlines, code
        ),
        can_approve = true
    }
end

function M:create_plugin(ctx)
    _state.ctx = ctx

    -- Register command: /lua-runtime (always available)
    ctx:register_command(
        "/lua-runtime",
        function(args_str)
            args_str = (args_str or ""):match("^%s*(.-)%s*$") or ""

            if args_str == "" or args_str == "help" then
                return [[Lua Runtime Plugin

Execute Lua code inline in Luna's process with full access to internal state.

Commands:
    /lua-runtime on        Enable Runtime Lua
    /lua-runtime off       Disable Runtime Lua
    /lua-runtime status    Show current status

Tool:
    run_inline_lua - Execute Lua code with full Luna context access
    (only available when runtime is enabled)

WARNING: When enabled, AI can modify Luna's behavior, corrupt sessions,
    or break the instance. Each execution requires user approval.
]]
            end

            if args_str == "on" then
                _state.enabled = true
                ctx:register_tool(
                    "run_inline_lua",
                    run_inline_lua,
                    "WARNING: INTERNAL DEBUGGING ONLY - Execute Lua code with full Luna internal access. NOT for general programming!",
                    {
                        type = "object",
                        properties = {
                            code = {
                                type = "string",
                                description = "Lua code to execute. Has access to 'ctx', 'app', 'log', 'os', 'io'. ONLY for debugging."
                            }
                        },
                        required = {"code"}
                    },
                    false,  -- auto_approved = false, always requires approval
                    format_arguments,
                    generate_preview
                )
                log.warn("[LUA-RUNTIME] Runtime Lua ENABLED")
                return ""
            elseif args_str == "off" then
                _state.enabled = false
                ctx:unregister_tool("run_inline_lua")
                log.error("[LUA-RUNTIME] Runtime Lua DISABLED")
                return ""
            elseif args_str == "status" then
                local s = _state.enabled and "ENABLED" or "DISABLED"
                log.success("[LUA-RUNTIME] Runtime Lua: " .. s)
                return ""
            else
                return "Unknown: " .. args_str .. ". Use on, off, status, or help."
            end
        end,
        "Enable/disable Lua runtime (execute Lua inline in Luna's process)"
    )
end

return M
