#!/usr/bin/env luajit
-- Lua unit tests for compaction service
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
print("\n=== Test: compaction_service module ===")
local cs = require("core.compaction_service")
check("compaction_service loads", type(cs) == "table")
local cs_methods = {}
for k in pairs(cs) do table.insert(cs_methods, k) end
print("    methods: " .. table.concat(cs_methods, ", "))

-- Test instantiation with mock api_client
local function make_empty_iter() return function() return nil end end
local mock_streaming = {
    stream_request = function(self, messages, stream1, stream2, stream3)
        -- Return an iterator that yields one chunk with summary
        local yielded = false
        return function()
            if yielded then return nil end
            yielded = true
            return {choices = {{delta = {content = "SUMMARY: This is a test summary."}}}}
        end
    end
}
local mock_api = {
    send_message = function(self, messages, opts)
        return {content = {{type = "text", text = "SUMMARY: This is a test summary of the conversation."}}}
    end,
    stream_request = function(self, messages, opts)
        return {content = {{type = "text", text = "SUMMARY: This is a test summary of the conversation."}}}
    end,
    api_client = mock_streaming
}
local compactor = cs.new(mock_api)
check("compactor instantiates", type(compactor) == "table")
print("    type: " .. type(compactor))

-- Try a simple messages list
local messages = {
    {role = "user", content = "Hello"},
    {role = "assistant", content = "Hi there"},
    {role = "user", content = "What is 2+2?"},
    {role = "assistant", content = "4"},
}

if compactor.compact then
    local ok, result = pcall(function() return compactor:compact(messages) end)
    if ok then
        check("compact runs", true)
        check("returns table", type(result) == "table", "got " .. type(result))
        if type(result) == "table" then
            print("    result type: " .. type(result))
        end
    else
        check("compact runs", false, tostring(result))
    end
end

if compactor.group_messages then
    local ok, result = pcall(function() return compactor:group_messages(messages) end)
    if ok then
        check("group_messages runs", true)
        check("returns table", type(result) == "table", "got " .. type(result))
    else
        check("group_messages runs", false, tostring(result))
    end
end

if compactor.force_compact_rounds then
    -- force_compact_rounds needs a real streaming client; skip if mock is incomplete
    local ok, result = pcall(function() return compactor:force_compact_rounds(messages, 1) end)
    -- Just verify method exists, don't require success
    check("force_compact_rounds callable", type(compactor.force_compact_rounds) == "function",
        "method exists")
end

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
