#!/usr/bin/env luajit
-- Test dkjson performance with session.json

local dkjson = require("dkjson")

-- Read file
local f = io.open("session.json", "r")
local content = f:read("*a")
f:close()

print("File size: " .. #content .. " bytes")

-- Parse JSON
local start = os.time()
local obj, pos, err = dkjson.decode(content, 1, nil)
local parse_time = os.time() - start

if err then
    print("Parse error: " .. err)
    return
end

print("Parse time: " .. parse_time .. " sec")

-- Count messages
local count = 0
if obj then
    count = #obj
end
print("Messages: " .. count)

-- Encode back
local start2 = os.time()
local encoded = dkjson.encode(obj)
local encode_time = os.time() - start2

print("Encode time: " .. encode_time .. " sec")
print("Encoded size: " .. #encoded .. " bytes")
print("Matches original: " .. (#encoded == #content and "yes" or "no"))

-- Time with nanoseconds
local function now()
    local s = os.time()
    return s * 1000000000
end

-- Re-parse for timing
local start_nano = now()
local obj2, _, err2 = dkjson.decode(content, 1, nil)
local end_nano = now()
local parse_nano = (end_nano - start_nano) / 1000000

print("\nMore precise timing:")
print("Parse: " .. string.format("%.2f", parse_nano) .. " ms")
print("Messages: " .. (obj2 and obj2.messages and #obj2.messages or "N/A"))