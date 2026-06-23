#!/usr/bin/env luajit
-- Lua tests for streaming_client module
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

local sc = require("core.streaming_client")
local client = sc.new()

-- ============================================================
print("\n=== Test: initialization ===")
check("client is table", type(client) == "table")

-- ============================================================
print("\n=== Test: methods exist ===")
check("stream_request is function", type(client.stream_request) == "function")
check("reset is function", type(client.reset) == "function")

-- ============================================================
print("\n=== Test: reset ===")
local ok, err = pcall(function() client:reset() end)
check("reset runs without error", ok, tostring(err))

-- ============================================================
print("\n=== Test: _recovery_attempted ===")
check("_recovery_attempted is boolean", type(client._recovery_attempted) == "boolean")

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
