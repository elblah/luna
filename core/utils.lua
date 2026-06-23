-- Core utility functions for Luna
local M = {}

-- Escape special Lua pattern characters
-- Makes a string safe to use as a literal pattern in gsub/find
function M.escape_pattern(s)
    if not s then return nil end
    return s:gsub("[%(%)%.%%%+%-%*%?%[%^%$%]]", "%%%1")
end

-- Replace string with proper literal matching and limit support
-- Works correctly on Lua 5.1 (LuaJIT) and Lua 5.3
-- Returns: (new_content, count_of_replacements)
function M.replace_string(content, old_string, new_string, limit)
    if not content or not old_string then
        return content, 0
    end
    
    local escaped = M.escape_pattern(old_string)
    local result = {}
    local count = 0
    local pos = 1
    
    while pos <= #content do
        local start_pos, end_pos = content:find(escaped, pos)
        if not start_pos then
            table.insert(result, content:sub(pos))
            break
        end
        
        count = count + 1
        
        if limit and count > limit then
            table.insert(result, content:sub(pos, end_pos))
        else
            table.insert(result, content:sub(pos, start_pos - 1))
            table.insert(result, new_string)
        end
        
        pos = end_pos + 1
        
        if limit and count >= limit then
            table.insert(result, content:sub(pos))
            break
        end
    end
    
    return table.concat(result), count
end

return M
