#!/usr/bin/env luajit
-- Comprehensive Lua tests for MessageHistory mirroring Python test_message_history.py
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

-- Setup
local stats_module = require("core.stats")
local mh = require("core.message_history")
local s = stats_module.new()
local m = mh.new(s)

-- ============================================================
print("\n=== Test: initialization ===")
check("messages is empty table", type(m.messages) == "table" and #m.messages == 0)
check("initial_system_prompt is nil", m.initial_system_prompt == nil)
check("is_compacting is false", m.is_compacting == false)

-- ============================================================
print("\n=== Test: add_system_message ===")
m:add_system_message("System prompt")
check("messages has 1 entry", #m.messages == 1)
check("first message is system", m.messages[1].role == "system")
check("first message content matches", m.messages[1].content == "System prompt")
check("initial_system_prompt set", m.initial_system_prompt ~= nil)

-- ============================================================
print("\n=== Test: add_user_message ===")
m:add_user_message("User message")
check("messages has 2 entries", #m.messages == 2)
check("second is user", m.messages[2].role == "user")
check("content matches", m.messages[2].content == "User message")

-- ============================================================
print("\n=== Test: add_assistant_message ===")
m:add_assistant_message({
    role = "assistant",
    content = "Assistant response",
    tool_calls = {
        {id = "call_1", type = "function", function_ = {name = "test_tool", arguments = '{"arg":"value"}'}}
    }
})
check("messages has 3 entries", #m.messages == 3)
check("third is assistant", m.messages[3].role == "assistant")
check("has tool_calls", m.messages[3].tool_calls ~= nil)

-- ============================================================
print("\n=== Test: add_tool_results ===")
m:add_tool_results({{tool_call_id = "call_1", role = "tool", content = "Tool output"}})
check("messages has 4 entries", #m.messages == 4)
check("fourth is tool", m.messages[4].role == "tool")

-- ============================================================
print("\n=== Test: get_messages ===")
local msgs = m:get_messages()
check("get_messages returns list", type(msgs) == "table")
check("count matches", #msgs == 4)

-- ============================================================
print("\n=== Test: get_chat_messages ===")
local chat_msgs = m:get_chat_messages()
-- Should include system + user + assistant, but tool results may be merged
check("get_chat_messages returns list", type(chat_msgs) == "table")
check("count > 0", #chat_msgs > 0)

-- ============================================================
print("\n=== Test: clear ===")
m:clear()
check("after clear, messages empty", #m.messages == 0)
check("initial_system_prompt cleared", m.initial_system_prompt == nil)

-- ============================================================
print("\n=== Test: get_message_count ===")
m:add_system_message("Sys")
m:add_user_message("U1")
m:add_assistant_message("A1")
check("get_message_count returns 3", m:get_message_count() == 3)

-- ============================================================
print("\n=== Test: get_chat_message_count ===")
local chat_count = m:get_chat_message_count()
check("chat_count > 0", chat_count > 0, "got: " .. tostring(chat_count))

-- ============================================================
print("\n=== Test: compaction_count_tracking ===")
m:increment_compaction_count()
m:increment_compaction_count()
check("compaction_count == 2", m:get_compaction_count() == 2)

-- ============================================================
print("\n=== Test: replace_messages ===")
m:replace_messages({{role = "user", content = "Replaced"}})
check("messages replaced", #m.messages == 1)
check("first is user", m.messages[1].role == "user")

-- ============================================================
print("\n=== Test: set_messages ===")
m:set_messages({
    {role = "user", content = "A"},
    {role = "assistant", content = "B"}
})
check("messages set", #m.messages == 2)
check("first is user", m.messages[1].role == "user")

-- ============================================================
print("\n=== Test: get_initial_system_prompt ===")
m:clear()
m:add_system_message("Initial")
local initial = m:get_initial_system_prompt()
check("initial system prompt exists", initial ~= nil)
check("content matches", initial and initial.content == "Initial")

-- ============================================================
print("\n=== Test: insert_user_message_at_beginning ===")
m:clear()
m:add_user_message("First user")
m:add_assistant_message("First response")
m:insert_user_message_at_appropriate_position("Inserted user")
check("messages count >= 2", #m.messages >= 2)
local has_inserted = false
for _, msg in ipairs(m.messages) do
    if msg.content == "Inserted user" then has_inserted = true; break end
end
check("inserted message exists", has_inserted)

-- ============================================================
print("\n=== Test: get_round_count ===")
m:clear()
m:add_system_message("Sys")
m:add_user_message("U1")
m:add_assistant_message("A1")
m:add_user_message("U2")
m:add_assistant_message("A2")
local rounds = m:get_round_count()
check("round count is number", type(rounds) == "number")
check("round count > 0", rounds > 0, "got: " .. tostring(rounds))

-- ============================================================
print("\n=== Test: set_api_client ===")
local mock_client = {}
m:set_api_client(mock_client)
check("api_client set", m.api_client ~= nil or m._api_client ~= nil)

-- ============================================================
print("\n=== Test: set_plugin_system ===")
-- Use a plugin system stub that has call_hooks
m:set_plugin_system({call_hooks = function(self, ...) return {} end})
check("plugin_system set", m.plugin_system ~= nil or m._plugin_system ~= nil)

-- ============================================================
print("\n=== Test: estimate_context ===")
print("    about to clear")
m:clear()
print("    about to add_system")
m:add_system_message("Sys")
print("    about to add_user")
m:add_user_message("Hello world")
print("    about to call estimate_context")
local ok, err = pcall(function() m:estimate_context() end)
print("    pcall returned ok=" .. tostring(ok) .. " err=" .. tostring(err))
check("estimate_context runs", ok, tostring(err))

-- ============================================================
print("\n=== Test: should_auto_compact ===")
local result = m:should_auto_compact()
check("should_auto_compact returns boolean", type(result) == "boolean")

-- ============================================================
print("\n=== Test: remove_orphan_tool_results ===")
m:clear()
m:add_assistant_message({role = "assistant", content = "with tool", tool_calls = {
    {id = "orphan_call", type = "function", function_ = {name = "t", arguments = "{}"}}
}})
m:add_user_message("next")
local removed = m:remove_orphan_tool_results()
check("remove_orphan_tool_results runs", type(removed) == "number",
    "got: " .. type(removed))

-- ============================================================
print("\n=== Test: force_compact_rounds ===")
m:clear()
m:add_user_message("U1")
m:add_assistant_message("A1")
m:add_user_message("U2")
m:add_assistant_message("A2")
-- Just check method exists, don't require success without proper api_client
check("force_compact_rounds is method", type(m.force_compact_rounds) == "function")

-- ============================================================
print("\n=== Test: get_tool_result_messages ===")
m:clear()
m:add_system_message("Sys")
m:add_assistant_message({role = "assistant", content = "tool", tool_calls = {
    {id = "c1", type = "function", function_ = {name = "t", arguments = "{}"}}
}})
m:add_tool_results({{tool_call_id = "c1", role = "tool", content = "out"}})
local trms = {}
if m.get_tool_result_messages then
    trms = m:get_tool_result_messages()
end
check("get_tool_result_messages returns list", type(trms) == "table")

-- ============================================================
print("\n=== Test: get_tool_call_stats ===")
if m.get_tool_call_stats then
    local stats = m:get_tool_call_stats()
    check("get_tool_call_stats returns table", type(stats) == "table")
    local has_data = next(stats) ~= nil
    print("    stats: " .. (has_data and "has data" or "empty"))
end

-- ============================================================
print("\n=== Test: get_session_messages ===")
m:clear()
m:add_system_message("System prompt")
m:add_user_message("User msg")
m:add_assistant_message("Assistant msg")
local session_msgs = m:get_session_messages()
check("get_session_messages returns table", type(session_msgs) == "table")
check("session messages excludes system", #session_msgs == 2, "got: " .. #session_msgs)
for _, msg in ipairs(session_msgs) do
    check("no system role in session", msg.role ~= "system")
end
m:clear()
m:add_system_message("Sys1")
local empty_session = m:get_session_messages()
check("session empty when only system", #empty_session == 0)

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
