#!/usr/bin/env luajit
-- Test: popen + curl streaming

local start = os.time()

print("Starting at " .. start)

local handle = io.popen("curl -s -w '\\nTIME:%{time_total}s' https://httpbin.org/delay/3")

local chunk_num = 0
for line in handle:lines() do
    chunk_num = chunk_num + 1
    local elapsed = os.time() - start
    print("[" .. elapsed .. "s] chunk " .. chunk_num .. ": " .. line)
end

handle:close()
local end_time = os.time()
print("Done at " .. end_time .. ", total " .. (end_time - start) .. "s")