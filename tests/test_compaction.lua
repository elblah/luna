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

-- Methods exist (no mock-driven end-to-end — needs real API client)
check("compact is function", type(compactor.compact) == "function")
check("group_messages is function", type(compactor.group_messages) == "function")
check("force_compact_rounds is function", type(compactor.force_compact_rounds) == "function")

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
