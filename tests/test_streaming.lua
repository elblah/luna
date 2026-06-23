#!/usr/bin/env luajit
-- Lua unit tests for streaming client internals and tool executor
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
print("\n=== Test: streaming_client methods ===")
local sc = require("core.streaming_client")
check("streaming_client loads", type(sc) == "table")
local sc_methods = {}
for k in pairs(sc) do table.insert(sc_methods, k) end
check("has methods", #sc_methods > 0)
print("    methods: " .. table.concat(sc_methods, ", "))

-- Check key methods exist
local required = {"new", "process_with_colorization", "reset", "_add_tool_definitions",
                  "_build_headers", "_format_messages", "update_token_stats"}
for _, m in ipairs(required) do
    check("has " .. m, type(sc[m]) == "function")
end

-- ============================================================
print("\n=== Test: anthropic_client methods ===")
local ac = require("core.anthropic_client")
check("anthropic_client loads", type(ac) == "table")
local ac_methods = {}
for k in pairs(ac) do table.insert(ac_methods, k) end
check("has methods", #ac_methods > 0)
print("    methods: " .. table.concat(ac_methods, ", "))

local required_ac = {"new", "_calculate_backoff", "_wait_for_retry", "stream_request",
                     "_build_headers", "_prepare_request_data", "process_with_colorization",
                     "reset_colorizer"}
for _, m in ipairs(required_ac) do
    check("has " .. m, type(ac[m]) == "function")
end

-- ============================================================
print("\n=== Test: tool_executor ===")
local te = require("core.tool_executor")
check("tool_executor loads", type(te) == "table")
check("ToolExecutor alias", type(te.ToolExecutor) == "table" or type(te.new) == "function")
check("new is function", type(te.new) == "function")
local te_methods = {}
for k in pairs(te) do table.insert(te_methods, k) end
print("    methods: " .. table.concat(te_methods, ", "))

-- Create a mock aicoder for executor
local mock_ac = {
    config = {sandbox = false, current_dir = "."},
    stats = nil,
    file_access_tracker = require("core.file_access_tracker"),
}
local exec = te.new(mock_ac)
check("executor created", type(exec) == "table")
check("executor has execute_tool_calls", type(exec.execute_tool_calls) == "function")
check("executor has is_guidance_mode", type(exec.is_guidance_mode) == "function")

-- ============================================================
print("\n=== Test: tool_manager factory ===")
local tm = require("core.tool_manager")
check("tool_manager loads", type(tm) == "table")
check("ToolManager alias", type(tm.ToolManager) == "table")
check("new is function", type(tm.new) == "function")

-- Check if we can construct a minimal aicoder
local mock_aicoder = {
    config = {sandbox = false, current_dir = "."},
    stats = nil,
    tool_executor = nil,
}
local mgr = tm.new(mock_aicoder)
check("manager constructed", type(mgr) == "table")
check("has get_tool_definitions", type(mgr.get_tool_definitions) == "function" or type(mgr["get_tool_definitions"]) == "function")
check("has execute_tool_call", type(mgr.execute_tool_call) == "function")
check("has needs_approval", type(mgr.needs_approval) == "function")

-- ============================================================
print("\n=== Test: plugin_system ===")
local ps = require("core.plugin_system")
check("plugin_system loads", type(ps) == "table")
check("PluginSystem alias", type(ps.PluginSystem) == "table")
check("PluginContext alias", type(ps.PluginContext) == "table")
check("new is function", type(ps.new) == "function")

-- ============================================================
print("\n=== Test: compaction_service ===")
local cs = require("core.compaction_service")
check("compaction_service loads", type(cs) == "table")
check("CompactionService alias", type(cs.CompactionService) == "table")
check("MessageGroup alias", type(cs.MessageGroup) == "table")
check("new is function", type(cs.new) == "function")
-- compact etc. are instance methods, check on instance
local fake_api = {stream_request = function() end}
local cs_inst = cs.new(fake_api)
check("compact is function", type(cs_inst.compact) == "function")
check("force_compact_rounds is function", type(cs_inst.force_compact_rounds) == "function")
check("force_compact_messages is function", type(cs_inst.force_compact_messages) == "function")
check("group_messages is function", type(cs_inst.group_messages) == "function")
check("classify_messages is function", type(cs.classify_messages) == "function")

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
