#!/usr/bin/env luajit
-- Lua unit tests for core modules
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
print("\n=== Test: message_history ===")
local mh = require("core.message_history")
check("new is function", type(mh.new) == "function")
check("MessageHistory alias exists", type(mh.MessageHistory) == "table")

local h = mh.new(nil)
local has_add = type(h.add_user_message) == "function" or type(h.add_system_message) == "function"
check("history instance has add", has_add)
local has_get = type(h.get_messages) == "function" or type(h.messages) == "table"
check("history instance has get_messages", has_get)

-- Test PRUNE constants exist
check("PRUNE_TOOL_MESSAGE exists", type(mh.PRUNE_TOOL_MESSAGE) == "string")
check("PRUNE_PROTECTION_THRESHOLD exists", type(mh.PRUNE_PROTECTION_THRESHOLD) == "number")

-- ============================================================
print("\n=== Test: stats ===")
local stats = require("core.stats")
check("Stats class alias exists", type(stats.Stats) == "table")
check("new is function", type(stats.new) == "function")

local s = stats.new()
check("stats instance is table", type(s) == "table")
local has_method = type(s.increment_api_requests) == "function" or type(s.add_tokens) == "function"
check("stats has tracking method", has_method)

-- ============================================================
print("\n=== Test: file_access_tracker ===")
local fat = require("core.file_access_tracker")
check("FileAccessTracker alias exists", type(fat.FileAccessTracker) == "table")
check("record_read is function", type(fat.record_read) == "function")
check("was_file_read is function", type(fat.was_file_read) == "function")
check("get_read_count is function", type(fat.get_read_count) == "function")
check("get_all_read_files is function", type(fat.get_all_read_files) == "function")
check("clear_state is function", type(fat.clear_state) == "function")

-- Functional
fat.clear_state()
check("clear_state works", fat.get_read_count() == 0)
fat.record_read("/test/path")
check("record_read increments count", fat.get_read_count() == 1)
check("was_file_read returns true", fat.was_file_read("/test/path") == true)
check("was_file_read returns false for unread", fat.was_file_read("/other") == false)
local all = fat.get_all_read_files()
check("get_all_read_files returns table with entry", type(all) == "table", "got type: " .. type(all))
fat.clear_state()

-- ============================================================
print("\n=== Test: compaction_service ===")
local cs = require("core.compaction_service")
check("CompactionService alias exists", type(cs.CompactionService) == "table")
check("MessageGroup alias exists", type(cs.MessageGroup) == "table")
check("new is function", type(cs.new) == "function")

-- ============================================================
print("\n=== Test: tool_executor ===")
local te = require("core.tool_executor")
check("ToolExecutor alias exists", type(te.ToolExecutor) == "table")
check("new is function", type(te.new) == "function")

-- ============================================================
print("\n=== Test: tool_formatter ===")
local tf = require("core.tool_formatter")
check("ToolFormatter alias exists", type(tf.ToolFormatter) == "table")
check("format_for_ai is function", type(tf.format_for_ai) == "function")
check("format_for_display is function", type(tf.format_for_display) == "function")
check("format_file_result is function", type(tf.format_file_result) == "function")
check("colorize_diff is function", type(tf.colorize_diff) == "function")

-- ============================================================
print("\n=== Test: plugin_system ===")
local ps = require("core.plugin_system")
check("PluginSystem alias exists", type(ps.PluginSystem) == "table")
check("PluginContext alias exists", type(ps.PluginContext) == "table")
check("new is function", type(ps.new) == "function")

-- ============================================================
print("\n=== Test: prompt_builder ===")
local pb = require("core.prompt_builder")
check("PromptBuilder alias exists", type(pb.PromptBuilder) == "table")
check("PromptContext alias exists", type(pb.PromptContext) == "table")
check("PromptOptions alias exists", type(pb.PromptOptions) == "table")
check("initialize is function", type(pb.initialize) == "function")
check("is_initialized is function", type(pb.is_initialized) == "function")
check("build is function", type(pb.build) == "function")

-- ============================================================
print("\n=== Test: tool_manager ===")
local tm = require("core.tool_manager")
check("ToolManager alias exists", type(tm.ToolManager) == "table")
check("new is function", type(tm.new) == "function")

local mgr = tm.new(nil)
check("manager instance is table", type(mgr) == "table")
local has_get_defs = type(mgr.get_tool_definitions) == "function" or type(mgr["get_tool_definitions"]) == "function"
check("manager has get_tool_definitions", has_get_defs)

-- ============================================================
print("\n=== Test: context_bar ===")
local cb = require("core.context_bar")
check("context_bar loads", type(cb) == "table")
local methods = {}
for k in pairs(cb) do table.insert(methods, k) end
check("context_bar has methods", #methods > 0)
print("    methods: " .. table.concat(methods, ", "))

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
