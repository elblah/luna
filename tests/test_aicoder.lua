#!/usr/bin/env luajit
-- Lua unit tests for aicoder, anthropic_client
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
print("\n=== Test: aicoder ===")
local aicoder_mod = require("core.aicoder")
check("aicoder module loads", type(aicoder_mod) == "table")
check("AICoder class is table", type(aicoder_mod.AICoder) == "table" or type(aicoder_mod.new) == "function")
check("new is function", type(aicoder_mod.new) == "function")

local AICoder = aicoder_mod.AICoder or aicoder_mod
local a = AICoder.new and AICoder.new() or aicoder_mod.new()
check("AICoder.new works", type(a) == "table")
check("has initialize", type(a.initialize) == "function" or type(a.initialize) == "function")
check("has run", type(a.run) == "function" or type(a["run"]) == "function")
check("has shutdown", type(a.shutdown) == "function")
check("has add_user_input", type(a.add_user_input) == "function")
check("has add_plugin_message", type(a.add_plugin_message) == "function")
check("has set_next_prompt", type(a.set_next_prompt) == "function")
check("has get_next_prompt", type(a.get_next_prompt) == "function")
check("has has_next_prompt", type(a.has_next_prompt) == "function")
check("has save_session", type(a.save_session) == "function")
check("has perform_auto_compaction", type(a.perform_auto_compaction) == "function")
check("has call_notify_hook", type(a.call_notify_hook) == "function")
check("has handle_test_message", type(a.handle_test_message) == "function")
check("has _setup_signal_handlers", type(a._setup_signal_handlers) == "function")
check("has register_auto_save", type(a.register_auto_save) == "function")
check("has _calculate_tool_tokens", type(a._calculate_tool_tokens) == "function")
check("has run_non_interactive", type(a.run_non_interactive) == "function")
check("has run_socket_only", type(a.run_socket_only) == "function")

-- ============================================================
print("\n=== Test: anthropic_client ===")
local ac = require("core.anthropic_client")
check("anthropic_client loads", type(ac) == "table")
check("AnthropicClient class is table", type(ac.AnthropicClient) == "table" or type(ac.new) == "function")
check("new is function", type(ac.new) == "function")

-- ============================================================
print("\n=== Test: ai_processor ===")
local aip = require("core.ai_processor")
check("ai_processor loads", type(aip) == "table")
check("AIProcessor class is table", type(aip.AIProcessor) == "table" or type(aip.new) == "function")
check("new is function", type(aip.new) == "function")
check("AIProcessorConfig class is table", type(aip.AIProcessorConfig) == "table")

-- ============================================================
print("\n=== Test: socket_server ===")
local ss = require("core.socket_server")
check("socket_server loads", type(ss) == "table")
check("SocketServer class is table", type(ss.SocketServer) == "table" or type(ss.new) == "function")
check("ss.new is function", type(ss.new) == "function")

-- ============================================================
print("\n=== Test: command_handler ===")
local ch = require("core.command_handler")
check("command_handler loads", type(ch) == "table")
check("CommandHandler is table", type(ch) == "table")
check("new is function", type(ch.new) == "function")

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
