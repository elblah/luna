#!/usr/bin/env luajit
-- Test readline completion with snippet completer

local ffi = require("ffi")

ffi.cdef[[
    void *malloc(size_t size);
    void free(void *);
    char *readline(const char *prompt);
    void add_history(const char *line);
    void using_history(void);
    
    typedef char **rl_completion_func_t(const char *, int, int);
    typedef char *rl_compentry_func_t(const char *, int);
    
    char **rl_completion_matches(const char *, rl_compentry_func_t *);
    rl_completion_func_t *rl_attempted_completion_function;
    int rl_attempted_completion_over;
]]

local rl = ffi.load("readline")
rl.using_history()

-- Simulate snippet completer
local function snippet_completer(text, state)
    print("snippet_completer called with: " .. tostring(text) .. " state:" .. tostring(state))
    
    if not text:match("^@@") then
        return nil
    end
    
    local matches = {"@@test", "@@snippet1", "@@snippet2"}
    
    if state == 0 then
        return matches
    end
    
    return nil
end

-- Set up completion
local handler = {
    completers = {snippet_completer}
}

rl.rl_attempted_completion_function = function(word, startpos, endpos)
    print("completion called with: " .. ffi.string(word) .. " startpos:" .. startpos .. " endpos:" .. endpos)
    local strword = ffi.string(word)
    local matches = {}
    
    for _, completer in ipairs(handler.completers) do
        local ok, result = pcall(completer, strword, 0)
        print("completer result:", ok, type(result))
        if ok and type(result) == "table" then
            for _, match in ipairs(result) do
                if match and match ~= "" then
                    local buf = ffi.C.malloc(#match + 1)
                    ffi.copy(buf, match)
                    table.insert(matches, buf)
                    print("added match:", match)
                end
            end
        end
    end
    
    if #matches == 0 then
        rl.rl_attempted_completion_over = 1
        print("no matches")
        return nil
    end
    
    print("returning", #matches, "matches")
    rl.rl_attempted_completion_over = 1
    return rl.rl_completion_matches(word, function(text, state)
        if state < #matches then
            return matches[state + 1]
        end
        return nil
    end)
end

print("Test readline completion - type @@t and press TAB")
print("")

while true do
    local line_ptr = rl.readline("> ")
    
    if line_ptr == nil then
        print("\nDone")
        break
    end
    
    local line = ffi.string(line_ptr)
    print("You typed: " .. line)
    
    if #line > 0 then
        rl.add_history(line)
    end
    
    ffi.C.free(line_ptr)
end
