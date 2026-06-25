#!/usr/bin/env luajit
-- Behavioral parity test: exercise key API methods and verify outputs
local failures = {}
local passes = 0

local function check(name, condition, detail)
    if condition then
        passes = passes + 1
        print("  PASS: " .. name)
    else
        table.insert(failures, name .. " - " .. tostring(detail or "no detail"))
        print("  FAIL: " .. name .. " - " .. tostring(detail or ""))
    end
end

-- ============================================================
-- Test 1: config module API
-- ============================================================
print("\n=== Test: config module ===")
local config = require("core.config")
check("config.thinking() returns string", type(config.thinking()) == "string")
check("config.max_retries() returns number", type(config.max_retries()) == "number")
check("config.max_backoff() returns number", type(config.max_backoff()) == "number")
check("config.sandbox_disabled() returns boolean", type(config.sandbox_disabled()) == "boolean")
check("config.detail_mode() returns boolean", type(config.detail_mode()) == "boolean")
check("config.yolo_mode() returns boolean", type(config.yolo_mode()) == "boolean")
check("config.in_tmux() returns boolean", type(config.in_tmux()) == "boolean")
check("config.socket_only() returns boolean", type(config.socket_only()) == "boolean")
check("config.api_key() returns string", type(config.api_key()) == "string" or config.api_key() == nil)
check("config.model() returns string", type(config.model()) == "string" or config.model() == nil)
check("config.ignore_dirs() returns table", type(config.ignore_dirs()) == "table")
check("config.ignore_patterns() returns table", type(config.ignore_patterns()) == "table")
check("config.effective_max_retries() returns number", type(config.effective_max_retries()) == "number")
check("config.effective_max_backoff() returns number", type(config.effective_max_backoff()) == "number")

-- Test setters don't error
local ok, err = pcall(function() config.set_thinking("on") end)
check("config.set_thinking('on') runs", ok, err)
ok, err = pcall(function() config.set_clear_thinking(true) end)
check("config.set_clear_thinking(true) runs", ok, err)
ok, err = pcall(function() config.set_reasoning_effort("low") end)
check("config.set_reasoning_effort('low') runs", ok, err)

-- Test _init aliases exist
check("config._init_thinking_from_env is function", type(config._init_thinking_from_env) == "function")
check("config._init_clear_thinking_from_env is function", type(config._init_clear_thinking_from_env) == "function")
check("config._init_reasoning_effort_from_env is function", type(config._init_reasoning_effort_from_env) == "function")

-- ============================================================
-- Test 2: token_estimator module
-- ============================================================
print("\n=== Test: token_estimator ===")
local te = require("core.token_estimator")
local msg_tokens = te.count_message_tokens("Hello, world!")
check("count_message_tokens returns number", type(msg_tokens) == "number" and msg_tokens > 0, "got " .. tostring(msg_tokens))

-- Aliases
check("cache_message is function", type(te.cache_message) == "function")
check("estimate_messages is function", type(te.estimate_messages) == "function")
check("set_tool_tokens is function", type(te.set_tool_tokens) == "function")

-- ============================================================
-- Test 3: log module
-- ============================================================
print("\n=== Test: log module ===")
local log = require("utils.log")
ok, err = pcall(function() log.info("test") end)
check("log.info runs", ok, err)
ok, err = pcall(function() log.warn("test") end)
check("log.warn runs", ok, err)
ok, err = pcall(function() log.error("test") end)
check("log.error runs", ok, err)
ok, err = pcall(function() log.debug("test") end)
check("log.debug runs", ok, err)
check("log.cyan is function", type(log.cyan) == "function")
check("log._get_colors is function", type(log._get_colors) == "function")
check("log._is_debug is function", type(log._is_debug) == "function")
check("log._get_error_log_path is function", type(log._get_error_log_path) == "function")
check("log._append_error_log is function", type(log._append_error_log) == "function")

-- ============================================================
-- Test 4: file_utils module
-- ============================================================
print("\n=== Test: file_utils ===")
local fu = require("utils.file_utils")
check("file_exists is function", type(fu.file_exists) == "function")
check("read_file is function", type(fu.read_file) == "function")
check("write_file is function", type(fu.write_file) == "function")
check("list_directory is function", type(fu.list_directory) == "function")

-- Functional: file_exists on a known file
local test_file = "/home/blah/poc/aicoder/luna/main.lua"
check("file_exists('main.lua') is true", fu.file_exists(test_file) == true)

-- Functional: write then read
local tmp = "/tmp/aicoder_test_" .. os.time() .. ".txt"
local wrote = fu.write_file(tmp, "hello world")
check("write_file returns truthy", wrote, "write_file returned " .. tostring(wrote))
local content = fu.read_file(tmp)
check("read_file returns written content", content == "hello world", "got: " .. tostring(content))
os.remove(tmp)

-- ============================================================
-- Test 5: diff_utils module
-- ============================================================
print("\n=== Test: diff_utils ===")
local du = require("utils.diff_utils")
check("diff_utils is a table", type(du) == "table")
check("colorize_diff is function", type(du.colorize_diff) == "function")
check("generate_unified_diff is function", type(du.generate_unified_diff) == "function")
check("generate_unified_diff_with_status is function", type(du.generate_unified_diff_with_status) == "function")
check("get_diff is function", type(du.get_diff) == "function")

-- Functional: get_diff (Lua's equivalent for in-memory diff)
local diff = du.get_diff("a\nb\nc\n", "a\nB\nc\n", "old.txt", "new.txt")
check("get_diff returns string", type(diff) == "string" and #diff > 0)

-- ============================================================
-- Test 6: json_utils module
-- ============================================================
print("\n=== Test: json_utils ===")
local ju = require("utils.json_utils")
check("write_file is function", type(ju.write_file) == "function")
check("read_file is function", type(ju.read_file) == "function")
check("read_file_safe is function", type(ju.read_file_safe) == "function")
check("is_valid is function", type(ju.is_valid) == "function")
check("parse_safe is function", type(ju.parse_safe) == "function")
check("is_valid('{}') == true", ju.is_valid("{}") == true)
check("is_valid('{x}') == false", ju.is_valid("{x}") == false)
check("parse_safe returns default on invalid", ju.parse_safe("{bad}", "default") == "default")

-- ============================================================
-- Test 7: tools module API
-- ============================================================
print("\n=== Test: tools ===")
for _, mod_name in ipairs({"read_file", "write_file", "edit_file", "list_directory", "grep", "run_shell_command"}) do
    local ok_load, mod = pcall(require, "tools." .. mod_name)
    check("tools." .. mod_name .. " loads", ok_load, mod)
    if ok_load then
        check(mod_name .. ".formatArguments exists", type(mod.formatArguments) == "function", "type: " .. type(mod.formatArguments))
        check(mod_name .. ".validateArguments exists", type(mod.validateArguments) == "function")
        check(mod_name .. ".generatePreview exists", type(mod.generatePreview) == "function")
        check(mod_name .. ".TOOL_DEFINITION exists", type(mod.TOOL_DEFINITION) == "table")
        check(mod_name .. ".TOOL_DEFINITION.formatArguments", type(mod.TOOL_DEFINITION.formatArguments) == "function")
    end
end

-- Test tool definitions are properly registered
local ToolManager = require("core.tool_manager")
local tm = ToolManager.new(nil)
check("ToolManager.new works", type(tm) == "table")
local defs = tm:get_tool_definitions()
check("get_tool_definitions returns table", type(defs) == "table")
check("def count >= 6", #defs >= 6, "got " .. #defs)

-- ============================================================
-- Test 8: command registry
-- ============================================================
print("\n=== Test: command registry ===")
local registry_mod = require("core.commands.registry")
check("CommandRegistry class exists", type(registry_mod.CommandRegistry) == "table")
check("SimplePluginCommand class exists", type(registry_mod.SimplePluginCommand) == "table")
check("_is_quit_exception is function", type(registry_mod._is_quit_exception) == "function")

local registry = registry_mod.CommandRegistry.new({})
local cmds = registry:get_all_commands()
check("get_all_commands returns table", type(cmds) == "table")
-- Use pairs to count since cmds is keyed by command name (string keys)
local cmds_count = 0
for _ in pairs(cmds) do cmds_count = cmds_count + 1 end
check("commands count >= 15", cmds_count >= 15, "got " .. cmds_count)

-- Test that all commands have execute and is_quit
for name, cmd in pairs(cmds) do
    check(name .. " has .get_name", type(cmd.get_name) == "function" or type(cmd.name) == "string")
    check(name .. " has .execute", type(cmd.execute) == "function")
end

-- Test specific commands exist
local found_quit = false
local found_help = false
for name, cmd in pairs(cmds) do
    if name == "quit" then found_quit = true end
    if name == "help" then found_help = true end
end
check("quit command registered", found_quit)
check("help command registered", found_help)

-- ============================================================
-- Test 9: datetime_utils
-- ============================================================
print("\n=== Test: datetime_utils ===")
local dtu = require("utils.datetime_utils")
check("datetime_utils is table", type(dtu) == "table")
local dt_methods = {}
for k in pairs(dtu) do table.insert(dt_methods, k) end
check("datetime_utils has methods", #dt_methods > 0, "got " .. #dt_methods)
print("    methods: " .. table.concat(dt_methods, ", "))

-- ============================================================
-- Test 10: message_history
-- ============================================================
print("\n=== Test: message_history ===")
local mh = require("core.message_history")
local history = mh.new()
check("message_history.new() works", type(history) == "table" or history ~= nil)

-- ============================================================
-- Test 11: input_handler
-- ============================================================
print("\n=== Test: input_handler ===")
local ih = require("core.input_handler")
check("input_handler is table", type(ih) == "table")

-- ============================================================
-- Test 13: temp_file_utils
-- ============================================================
print("\n=== Test: temp_file_utils ===")
local tfu = require("utils.temp_file_utils")
check("write_temp_file is function", type(tfu.write_temp_file) == "function")
check("delete_file is function", type(tfu.delete_file) == "function")
check("delete_file_sync is function", type(tfu.delete_file_sync) == "function")

-- ============================================================
-- Test 14: stats module
-- ============================================================
print("\n=== Test: stats ===")
local stats = require("core.stats")
check("stats is table", type(stats) == "table")
local stats_methods = {}
for k in pairs(stats) do table.insert(stats_methods, k) end
check("stats has methods", #stats_methods > 0)

-- ============================================================
-- Test 15: file_access_tracker
-- ============================================================
print("\n=== Test: file_access_tracker ===")
local fat = require("core.file_access_tracker")
check("file_access_tracker is table", type(fat) == "table")

-- ============================================================
-- Summary
-- ============================================================
print(string.format("\n=================================================="))
print(string.format("Behavioral Parity Test Results: %d passed, %d failed", passes, #failures))
if #failures > 0 then
    print("\nFAILURES:")
    for _, f in ipairs(failures) do
        print("  " .. f)
    end
    os.exit(1)
end
print("All behavioral checks passed")
