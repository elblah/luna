#!/usr/bin/env luajit
-- Lua tests for config module (mirrors test_config.py)
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

local config = require("core.config")

-- ============================================================
print("\n=== Test: colors ===")
check("colors is table", type(config.colors) == "table")
check("colors.reset exists", config.colors.reset ~= nil)
check("colors.red exists", config.colors.red ~= nil)
check("colors.green exists", config.colors.green ~= nil)
check("colors.yellow exists", config.colors.yellow ~= nil)

-- ============================================================
print("\n=== Test: yolo_mode ===")
check("yolo_mode is boolean", type(config.yolo_mode()) == "boolean")
if config.get_yolo_mode then
    check("get_yolo_mode is boolean", type(config.get_yolo_mode()) == "boolean")
end
-- set/get roundtrip
local orig = config.yolo_mode()
config.set_yolo_mode(true)
check("set_yolo_mode(true) works", config.yolo_mode() == true)
config.set_yolo_mode(false)
check("set_yolo_mode(false) works", config.yolo_mode() == false)
config.set_yolo_mode(orig)

-- ============================================================
print("\n=== Test: sandbox_disabled ===")
check("sandbox_disabled is boolean", type(config.sandbox_disabled()) == "boolean")
local orig_sandbox = config.sandbox_disabled()
config.set_sandbox_disabled(true)
check("set_sandbox_disabled(true) works", config.sandbox_disabled() == true)
config.set_sandbox_disabled(false)
check("set_sandbox_disabled(false) works", config.sandbox_disabled() == false)
config.set_sandbox_disabled(orig_sandbox)

-- ============================================================
print("\n=== Test: detail_mode ===")
check("detail_mode is boolean", type(config.detail_mode()) == "boolean")
local orig_detail = config.detail_mode()
config.set_detail_mode(true)
check("set_detail_mode(true) works", config.detail_mode() == true)
config.set_detail_mode(false)
check("set_detail_mode(false) works", config.detail_mode() == false)
config.set_detail_mode(orig_detail)

-- ============================================================
print("\n=== Test: thinking ===")
check("thinking returns string", type(config.thinking()) == "string")

-- ============================================================
print("\n=== Test: clear_thinking ===")
check("clear_thinking returns string or nil", type(config.clear_thinking()) == "string" or config.clear_thinking() == nil)
if config.set_clear_thinking then
    local orig_ct = config.clear_thinking()
    config.set_clear_thinking("off")
    check("set_clear_thinking('off') works", config.clear_thinking() == "off")
    config.set_clear_thinking(orig_ct)
end

-- ============================================================
print("\n=== Test: reasoning_effort ===")
check("reasoning_effort returns string or nil", type(config.reasoning_effort()) == "string" or config.reasoning_effort() == nil)
if config.set_reasoning_effort then
    local orig_re = config.reasoning_effort()
    local ok, err = pcall(function() config.set_reasoning_effort("low") end)
    check("set_reasoning_effort('low') runs", ok, tostring(err))
    if orig_re then config.set_reasoning_effort(orig_re) end
end

-- ============================================================
print("\n=== Test: max_retries ===")
check("max_retries returns number", type(config.max_retries()) == "number")
check("effective_max_retries returns number", type(config.effective_max_retries()) == "number")

-- ============================================================
print("\n=== Test: max_backoff ===")
check("max_backoff returns number", type(config.max_backoff()) == "number")
check("effective_max_backoff returns number", type(config.effective_max_backoff()) == "number")

-- ============================================================
print("\n=== Test: socket_only ===")
check("socket_only is boolean", type(config.socket_only()) == "boolean")

-- ============================================================
print("\n=== Test: in_tmux ===")
check("in_tmux is boolean", type(config.in_tmux()) == "boolean")

-- ============================================================
print("\n=== Test: api_key ===")
check("api_key returns string or nil", type(config.api_key()) == "string" or config.api_key() == nil)

-- ============================================================
print("\n=== Test: model ===")
check("model returns string or nil", type(config.model()) == "string" or config.model() == nil)

-- ============================================================
print("\n=== Test: ignore_dirs ===")
check("ignore_dirs returns table", type(config.ignore_dirs()) == "table")

-- ============================================================
print("\n=== Test: ignore_patterns ===")
check("ignore_patterns returns table", type(config.ignore_patterns()) == "table")

-- ============================================================
print("\n=== Test: validate_config ===")
local ok, err = pcall(function() config.validate_config() end)
check("validate_config runs without error", ok, tostring(err))

-- ============================================================
print("\n=== Test: print_startup_info ===")
local ok2, err2 = pcall(function() config.print_startup_info() end)
check("print_startup_info runs without error", ok2, tostring(err2))

-- ============================================================
print("\n=== Test: tool_deny/allow ===")
if config.tools_deny then
    check("tools_deny returns table or nil", type(config.tools_deny()) == "table" or config.tools_deny() == nil)
end
if config.tools_allow then
    check("tools_allow returns table or nil", type(config.tools_allow()) == "table" or config.tools_allow() == nil)
end

-- ============================================================
print("\n=== Test: plugins_deny/allow ===")
if config.plugins_deny then
    check("plugins_deny returns table or nil", type(config.plugins_deny()) == "table" or config.plugins_deny() == nil)
end
if config.plugins_allow then
    check("plugins_allow returns table or nil", type(config.plugins_allow()) == "table" or config.plugins_allow() == nil)
end

-- ============================================================
print("\n=== Test: reset ===")
if config.reset then
    local ok3, err3 = pcall(function() config.reset() end)
    check("reset runs without error", ok3, tostring(err3))
end

-- ============================================================
print("\n=== Test: session_file ===")
local session_f = config.session_file()
check("session_file returns string", type(session_f) == "string")
-- session_file is an os.getenv() wrapper; can't set env in this LuaJIT
-- so just verify consistency
check("session_file matches AICODER_SESSION_FILE or SESSION_JSON_FILE env",
    session_f == (os.getenv("AICODER_SESSION_FILE") or os.getenv("SESSION_JSON_FILE") or ""))

-- ============================================================
print("\n=== Test: session_output_file ===")
local out_f = config.session_output_file()
check("session_output_file returns string", type(out_f) == "string")
check("session_output_file matches AICODER_SESSION_OUTPUT or SESSION_OUTPUT_FILE env",
    out_f == (os.getenv("AICODER_SESSION_OUTPUT") or os.getenv("SESSION_OUTPUT_FILE") or ""))

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
