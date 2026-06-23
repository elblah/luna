#!/usr/bin/env luajit
-- Test: popen streaming with local command

local start = os.time()

print("Starting at " .. os.date("%H:%M:%S"))

local handle = io.popen('for i in 1 2 3 4 5 6 7 8 9 10; do echo "ooooooo $i"; sleep 2; done')

local chunk_num = 0
for line in handle:lines() do
    chunk_num = chunk_num + 1
    local elapsed = os.time() - start
    print("[" .. elapsed .. "s] chunk " .. chunk_num .. ": " .. line)
end

handle:close()
print("Done. Total " .. (os.time() - start) .. "s")