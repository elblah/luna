#!/usr/bin/env luajit
-- Lua tests for stats module (mirrors test_stats.py)
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

local stats_module = require("core.stats")
local s = stats_module.new()

-- ============================================================
print("\n=== Test: initialization ===")
check("api_requests == 0", s.api_requests == 0)
check("api_success == 0", s.api_success == 0)
check("api_errors == 0", s.api_errors == 0)
check("api_time_spent == 0", s.api_time_spent == 0)
check("messages_sent == 0", s.messages_sent == 0)
check("compactions == 0", s.compactions == 0)
check("prompt_tokens == 0", s.prompt_tokens == 0)
check("completion_tokens == 0", s.completion_tokens == 0)
check("current_prompt_size == 0", s.current_prompt_size == 0)
check("last_user_prompt == ''", s.last_user_prompt == "")

-- ============================================================
print("\n=== Test: incrementers ===")
s:increment_api_requests()
s:increment_api_requests()
check("api_requests == 2", s.api_requests == 2)

s:increment_api_success()
s:increment_api_success()
check("api_success == 2", s.api_success == 2)

s:increment_api_errors()
check("api_errors == 1", s.api_errors == 1)

s:increment_messages_sent()
check("messages_sent == 1", s.messages_sent == 1)

s:increment_compactions()
check("compactions == 1", s.compactions == 1)

-- ============================================================
print("\n=== Test: token tracking ===")
s:add_prompt_tokens(100)
check("prompt_tokens == 100", s.prompt_tokens == 100)
s:add_completion_tokens(50)
check("completion_tokens == 50", s.completion_tokens == 50)

-- ============================================================
print("\n=== Test: last_user_prompt ===")
s:set_last_user_prompt("Hello world")
check("last_user_prompt set", s.last_user_prompt == "Hello world")

-- ============================================================
print("\n=== Test: size tracking ===")
s:set_current_prompt_size(1000)
check("current_prompt_size == 1000", s.current_prompt_size == 1000)
s:mark_prompt_size_estimated()
check("current_prompt_size_estimated == true", s.current_prompt_size_estimated == true)

-- ============================================================
print("\n=== Test: usage_infos ===")
check("usage_infos is table", type(s.usage_infos) == "table")
s:add_usage_info({prompt_tokens = 10, completion_tokens = 5, total = 15})
check("usage_infos has 1 entry", #s.usage_infos == 1)

-- ============================================================
print("\n=== Test: reset ===")
s:reset()
check("after reset, api_requests == 0", s.api_requests == 0)
check("after reset, api_success == 0", s.api_success == 0)
check("after reset, messages_sent == 0", s.messages_sent == 0)
check("after reset, prompt_tokens == 0", s.prompt_tokens == 0)
check("after reset, completion_tokens == 0", s.completion_tokens == 0)

-- ============================================================
print("\n=== Test: add_api_time ===")
s:add_api_time(1.5)
check("api_time_spent > 0", s.api_time_spent > 0)

-- ============================================================
print("\n=== Test: add_tokens ===")
s:reset()
s:add_tokens(100, 50)
check("add_tokens sets prompt_tokens", s.prompt_tokens == 100)
check("add_tokens sets completion_tokens", s.completion_tokens == 50)

-- ============================================================
print("\n=== Test: increment_user_interactions ===")
s:reset()
s:increment_user_interactions()
check("user_interactions == 1", s.user_interactions == 1)

-- ============================================================
print("\n=== Test: print_stats ===")
s:reset()
local ok, err = pcall(function() s:print_stats() end)
check("print_stats runs without error", ok, tostring(err))

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
