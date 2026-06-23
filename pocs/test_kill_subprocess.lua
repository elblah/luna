#!/usr/bin/env luajit
-- Test Ctrl+C during long-running shell command

local ffi = require("ffi")

ffi.cdef[[
    void using_history(void);
    void add_history(const char *);
    char *readline(const char *prompt);
    void free(void *);
]]

-- Load readline
local rl = ffi.load("readline")
rl.using_history()
rl.add_history("/help")
rl.add_history("/quit")

print("Test: Run 'sleep 5' and press Ctrl+C")
print("Program should NOT exit, should return to prompt")
print("")

local function safe_readline(prompt)
    local ptr, err = rl.readline(prompt)
    if ptr == nil then
        return nil
    end
    return ptr
end

local running = true
local iteration = 0

while running do
    iteration = iteration + 1
    
    -- Show iteration count (proves we're still running)
    local ptr = safe_readline("[" .. iteration .. "]> ")
    
    if ptr == nil then
        print("(cancelled - still running)")
    else
        local line = ffi.string(ptr)
        rl.add_history(line)
        
        if line == "" then
            -- do nothing
        elseif line == "/quit" or line == "/q" then
            print("Goodbye!")
            running = false
        elseif line == "/sleep" then
            print("Starting 'sleep 5'...")
            print("Press Ctrl+C NOW if you want to test interrupt")
            local handle = io.popen("sleep 5")
            local result = handle:read("*a")
            handle:close()
            print("sleep completed (or was killed)")
        elseif line:sub(1, 1) == "/" then
            -- Command with possible args
            local parts = {}
            for word in line:gmatch("%S+") do
                table.insert(parts, word)
            end
            local cmd = parts[1]
            local arg = parts[2]
            
            if cmd == "/sleep" then
                local delay = tonumber(arg) or 5
                print("Starting 'sleep " .. delay .. "'...")
                print("Press Ctrl+C NOW if you want to test interrupt")
                local ok, err = pcall(function()
                    local handle = io.popen("sleep " .. delay)
                    local result = handle:read("*a")
                    handle:close()
                    return result
                end)
                if not ok then
                    print("(tool interrupted)")
                else
                    print("sleep completed")
                end
            else
                print("Unknown command: " .. line)
            end
        else
            print("You: " .. line)
        end
        
        ffi.C.free(ptr)
    end
end

print("Program exited gracefully")