#!/usr/bin/env luajit
-- Signal handling - simpler approach

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

print("Signal test: Ctrl+C cancels, Ctrl+D ignored, /quit exits")
print("")

local running = true

while running do
    local ptr = rl.readline("> ")
    
    if ptr == nil then
        -- NULL returned - could be Ctrl+C or Ctrl+D
        -- We cannot distinguish easily
        -- Both treated as "cancel current operation"
        print("(cancelled)")
    else
        local line = ffi.string(ptr)
        rl.add_history(line)
        
        if line == "" then
            -- Empty line, do nothing
        elseif line == "/quit" or line == "/q" then
            print("Goodbye!")
            running = false
        elseif line:sub(1,1) == "/" then
            print("Command: " .. line)
        else
            print("You: " .. line)
        end
        
        ffi.C.free(ptr)
    end
end