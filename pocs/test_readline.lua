#!/usr/bin/env luajit
-- readline completion - exact ILuaJIT approach

local ffi = require("ffi")

ffi.cdef[[
    void *malloc(size_t size);
    void free(void *);
    char *readline(const char *prompt);
    void add_history(const char *line);
    void using_history(void);
    
    // completion function types
    typedef char **rl_completion_func_t(const char *, int, int);
    typedef char *rl_compentry_func_t(const char *, int);
    
    // completion matching
    char **rl_completion_matches(const char *, rl_compentry_func_t *);
    
    // completion function pointer
    rl_completion_func_t *rl_attempted_completion_function;
    int rl_attempted_completion_over;
]]

local rl = ffi.load("readline")
rl.using_history()

-- Commands for completion
local commands = {
    "/help", "/quit", "/debug", "/model", "/compact",
    "/skills", "/shell", "/goal", "/retry", "/stats",
    "/tokens", "/theme", "/presets"
}

-- Pre-load history
for _, cmd in ipairs(commands) do
    rl.add_history(cmd)
end

-- Completion function (3 args: word, start, end)
function rl.rl_attempted_completion_function(word, startpos, endpos)
    local strword = ffi.string(word)
    local matches = {}
    
    for _, cmd in ipairs(commands) do
        if cmd:sub(1, #strword):lower() == strword:lower() then
            local buf = ffi.C.malloc(#cmd + 1)
            ffi.copy(buf, cmd)
            table.insert(matches, buf)
        end
    end
    
    if #matches == 0 then
        rl.rl_attempted_completion_over = 1
        return nil
    end
    
    rl.rl_attempted_completion_over = 1
    return rl.rl_completion_matches(word, function(text, state)
        if state < #matches then
            return matches[state + 1]
        end
        return nil
    end)
end

print("Readline completion test")
print("")

while true do
    local line_ptr = rl.readline("> ")
    
    if line_ptr == nil then
        print("\nDone")
        break
    end
    
    local line = ffi.string(line_ptr)
    
    if #line > 0 then
        rl.add_history(line)
        print("You: " .. line)
    end
    
    ffi.C.free(line_ptr)
end