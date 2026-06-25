#!/usr/bin/env luajit
-- Lua unit tests for commands and remaining modules
local pass = 0
local fail = 0
local function check(name, condition, detail)
    if condition then
        pass = pass + 1
        print("  PASS: " .. name)
    else
        fail = fail + 1
        print("  FAIL: " .. name .. " - " .. (detail or ""))
    end
end

-- ============================================================
print("\n=== Test: command registry & base ===")
local base = require("core.commands.base")
check("base loads", type(base) == "table")
check("CommandHandler alias", type(base.CommandHandler) == "table")

local reg = require("core.commands.registry")
check("registry loads", type(reg) == "table")
check("CommandRegistry alias", type(reg.CommandRegistry) == "table" or type(reg.new) == "function")
check("new is function", type(reg.new) == "function")

local ctx = {aicoder = {save_session = function() end, get_stats = function() return {} end}}
local r = reg.new(ctx)
check("registry created", type(r) == "table")
check("register_command is function", type(r.register_command) == "function")
check("execute_command is function", type(r.execute_command) == "function")
check("get_command is function", type(r.get_command) == "function")
check("list_commands is function", type(r.list_commands) == "function")

-- ============================================================
print("\n=== Test: individual commands load ===")
local cmd_names = {
    "compact", "debug", "detail", "edit", "help",
    "load", "memory", "new", "quit", "retry",
    "sandbox", "save", "stats", "thinking", "yolo"
}
for _, name in ipairs(cmd_names) do
    local ok, cmd = pcall(require, "core.commands." .. name)
    if ok then
        check("command '" .. name .. "' loads", type(cmd) == "table")
    else
        check("command '" .. name .. "' loads", false, tostring(cmd))
    end
end

-- ============================================================
print("\n=== Test: prompt_history ===")
local ph = require("core.prompt_history")
check("prompt_history loads", type(ph) == "table")
check("save_prompt is function", type(ph.save_prompt) == "function")
check("read_history is function", type(ph.read_history) == "function")

-- save & read roundtrip
ph.save_prompt("test prompt 1")
ph.save_prompt("test prompt 2")
ph.save_prompt("y")  -- should be skipped (Y/N response)
ph.save_prompt("")   -- should be skipped (empty)
ph.save_prompt("n")  -- should be skipped

local hist = ph.read_history()
check("read_history returns table", type(hist) == "table")
local count = 0
for _, _ in ipairs(hist) do count = count + 1 end
check("history has entries", count >= 2, "got: " .. count)
local first_prompt = nil
for _, e in ipairs(hist) do
    if e.prompt == "test prompt 1" then first_prompt = e.prompt break end
end
check("first entry 'test prompt 1' present", first_prompt == "test prompt 1")

-- ============================================================
print("\n=== Test: session_manager ===")
local sm = require("core.session_manager")
check("session_manager loads", type(sm) == "table")
check("new is function", type(sm.new) == "function")
check("process_with_ai is function", type(sm.process_with_ai) == "function")
-- private methods not exposed at module level

-- ============================================================
print("\n=== Test: markdown_colorizer ===")
local mc = require("core.markdown_colorizer")
check("markdown_colorizer loads", type(mc) == "table")
local method_count = 0
for _ in pairs(mc) do method_count = method_count + 1 end
check("markdown_colorizer has methods", method_count > 0, "count: " .. method_count)
print("    methods: " .. method_count)
for k, _ in pairs(mc) do print("      - " .. tostring(k)) end

-- ============================================================
print("\n=== Test: input_handler ===")
local ih = require("core.input_handler")
check("input_handler loads", type(ih) == "table")
local ih_count = 0
for _ in pairs(ih) do ih_count = ih_count + 1 end
check("input_handler has methods", ih_count > 0, "count: " .. ih_count)
for k, _ in pairs(ih) do print("      - " .. tostring(k)) end

-- ============================================================
print("\n=== Test: token_estimator ===")
local te = require("core.token_estimator")
check("token_estimator loads", type(te) == "table")
check("count_tokens is function", type(te.count_tokens) == "function")
check("count_message_tokens is function", type(te.count_message_tokens) == "function")
check("count_messages_tokens is function", type(te.count_messages_tokens) == "function")
check("clear_cache is function", type(te.clear_cache) == "function")
check("set_tools_tokens is function", type(te.set_tools_tokens) == "function")
check("get_tools_tokens is function", type(te.get_tools_tokens) == "function")
check("estimate_total_size is function", type(te.estimate_total_size) == "function")

-- estimate test
local n = te.count_tokens("Hello world, this is a test.")
check("count_tokens returns number > 0", type(n) == "number" and n > 0, "got: " .. tostring(n))

-- ============================================================
print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
