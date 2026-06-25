#!/usr/bin/env luajit
-- Lua unit tests for misc modules: colorizer, context_bar, prompt_builder
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
print("\n=== Test: markdown_colorizer ===")
local md = require("core.markdown_colorizer")
check("markdown_colorizer loads", type(md) == "table")
check("new is function", type(md.new) == "function")
check("colorize is function", type(md.colorize) == "function")
check("process_with_colorization is function", type(md.process_with_colorization) == "function")
check("reset_state is function", type(md.reset_state) == "function")
check("print_with_colorization is function", type(md.print_with_colorization) == "function")

-- Test colorize on a simple string
local c = md.new()
local result = c:colorize("**bold** and *italic*")
check("colorize returns string", type(result) == "string", "got: " .. tostring(result))
check("colorize output non-empty", #result > 0)

-- Code block
result = c:colorize("```lua\nprint('hi')\n```")
check("code block colorize returns string", type(result) == "string" and #result > 0)

-- ============================================================
print("\n=== Test: context_bar ===")
local cb = require("core.context_bar")
check("context_bar loads", type(cb) == "table")
check("new is function", type(cb.new) == "function")
check("create_progress_bar is function", type(cb.create_progress_bar) == "function")
check("format_context_bar is function", type(cb.format_context_bar) == "function")
check("print_context_bar is function", type(cb.print_context_bar) == "function")
check("print_context_bar_for_user is function", type(cb.print_context_bar_for_user) == "function")
check("get_current_hour is function", type(cb.get_current_hour) == "function")

-- create_progress_bar test
local bar = cb.create_progress_bar(50, 100, 10)
check("create_progress_bar(50%, 10) returns string", type(bar) == "string" and #bar > 0, "got: " .. tostring(bar))

local bar2 = cb.create_progress_bar(0, 100, 10)
check("create_progress_bar(0%, 10) returns string", type(bar2) == "string" and #bar2 > 0)

local bar3 = cb.create_progress_bar(100, 100, 10)
check("create_progress_bar(100%, 10) returns string", type(bar3) == "string" and #bar3 > 0)

-- get_current_hour (Python returns HH:MM:SS string, not int hour)
local h = cb.get_current_hour()
check("get_current_hour returns time string", type(h) == "string" and h:match("^%d%d:%d%d:%d%d$") ~= nil, "got: " .. tostring(h))

-- ============================================================
print("\n=== Test: prompt_builder ===")
local pb = require("core.prompt_builder")
check("prompt_builder loads", type(pb) == "table")
check("PromptBuilder alias", type(pb.PromptBuilder) == "table")
check("PromptContext alias", type(pb.PromptContext) == "table")
check("PromptOptions alias", type(pb.PromptOptions) == "table")
check("initialize is function", type(pb.initialize) == "function")
check("is_initialized is function", type(pb.is_initialized) == "function")
check("build is function", type(pb.build) == "function")

-- Initialize (use default template)
pb.initialize()
check("pb.initialize() runs", true)
check("is_initialized returns true after init", pb.is_initialized() == true)

-- build a prompt
local ctx = pb.PromptContext.new({
    aicoder = nil,
    system_prompt = "You are a test assistant.",
    messages = {{role = "user", content = "Hello"}},
})
local opts = pb.PromptOptions.new()
local result = pb.build(ctx, opts)
check("build returns string", type(result) == "string", "got: " .. type(result))
check("build result non-empty", #result > 0)

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

-- Test count_tokens
local n1 = te.count_tokens("hello world")
check("count_tokens('hello world') > 0", type(n1) == "number" and n1 > 0, "got: " .. tostring(n1))
local n2 = te.count_tokens("a much longer string with many words to count")
check("count_tokens longer > shorter", n2 > n1, "n1=" .. n1 .. " n2=" .. n2)

-- Test count_message_tokens
local msg_tokens = te.count_message_tokens({role = "user", content = "hello world"})
check("count_message_tokens returns number", type(msg_tokens) == "number" and msg_tokens > 0)

-- Test count_messages_tokens
local total = te.count_messages_tokens({{role = "user", content = "msg1"}, {role = "assistant", content = "msg2"}})
check("count_messages_tokens returns number", type(total) == "number" and total > 0)

-- estimate_total_size
te.set_tools_tokens(100)
local est = te.estimate_total_size({{role = "user", content = "test"}}, {})
check("estimate_total_size returns number", type(est) == "number" and est > 0, "got: " .. tostring(est))

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
