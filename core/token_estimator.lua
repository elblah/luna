-- Token estimation using TSV-style weighted character counting
-- Ported from Python core/token_estimator.py

local M = {}

-- Token estimation weights
local TOKEN_LETTER_WEIGHT = 4.2
local TOKEN_NUMBER_WEIGHT = 3.5
local TOKEN_PUNCTUATION_WEIGHT = 1.0
local TOKEN_WHITESPACE_WEIGHT = 0.15
local TOKEN_OTHER_WEIGHT = 3.0

-- Punctuation set for fast lookup
local PUNCTUATION_SET = {
    ["!"] = true, ["\""] = true, ["#"] = true, ["$"] = true, ["%"] = true,
    ["&"] = true, ["'"] = true, ["("] = true, [")"] = true, ["*"] = true,
    ["+"] = true, [","] = true, ["-"] = true, ["."] = true, ["/"] = true,
    [":"] = true, [";"] = true, ["<"] = true, ["="] = true, [">"] = true,
    ["?"] = true, ["@"] = true, ["["] = true, ["\\"] = true, ["]"] = true,
    ["^"] = true, ["_"] = true, ["`"] = true, ["{"] = true, ["|"] = true,
    ["}"] = true, ["~"] = true,
}

-- Caches
local _message_cache = {}
local _tools_tokens = 0
local _original_tool_tokens = 0
local _MAX_CACHE_SIZE = 1000

function M._estimate_weighted_tokens(text)
    if not text or #text == 0 then
        return 0
    end

    local letters = 0
    local numbers = 0
    local punctuation = 0
    local whitespace = 0
    local other = 0

    for i = 1, #text do
        local char = text:sub(i, i)
        local byte = string.byte(char)
        
        -- letters: a-z (97-122) or A-Z (65-90)
        if (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) then
            letters = letters + 1
        -- numbers: 0-9 (48-57)
        elseif byte >= 48 and byte <= 57 then
            numbers = numbers + 1
        -- punctuation from set
        elseif PUNCTUATION_SET[char] then
            punctuation = punctuation + 1
        -- whitespace
        elseif byte == 32 or byte == 9 or byte == 10 or byte == 13 then
            whitespace = whitespace + 1
        else
            other = other + 1
        end
    end

    local token_estimate = (
        letters / TOKEN_LETTER_WEIGHT +
        numbers / TOKEN_NUMBER_WEIGHT +
        punctuation * TOKEN_PUNCTUATION_WEIGHT +
        whitespace * TOKEN_WHITESPACE_WEIGHT +
        other / TOKEN_OTHER_WEIGHT
    )

    return math.max(0, math.floor(token_estimate + 0.5))
end

function M.count_tokens(text)
    if not text then
        return 0
    end
    return M._estimate_weighted_tokens(text)
end

function M.count_message_tokens(msg)
    if not msg then
        return 0
    end

    -- Use table pointer as cache key (unique per table instance)
    local msg_id = tostring(msg)
    
    -- Check cache first
    if _message_cache[msg_id] then
        return _message_cache[msg_id]
    end

    -- Serialize entire message to JSON for accurate estimation (like Python)
    local json = require("utils.json")
    local ok, json_str = pcall(function() return json.encode(msg) end)
    if not ok then
        -- Fallback to content string
        json_str = msg.content or tostring(msg)
    end

    local tokens = M._estimate_weighted_tokens(json_str)

    -- Cache management
    if #_message_cache > _MAX_CACHE_SIZE then
        _message_cache = {}
    end
    _message_cache[msg_id] = tokens

    return tokens
end

function M.count_messages_tokens(messages)
    if not messages or #messages == 0 then
        return _tools_tokens
    end

    local total = _tools_tokens
    for _, msg in ipairs(messages) do
        total = total + M.count_message_tokens(msg)
    end
    return total
end

function M.clear_cache()
    _message_cache = {}
    -- Preserve tool tokens like Python (they don't change during session)
end

function M.set_tools_tokens(tokens)
    _tools_tokens = tokens
end

function M.get_tools_tokens()
    return _tools_tokens
end

function M.get_original_tool_tokens()
    return _original_tool_tokens
end

function M.estimate_total_size(messages, tools)
    local msg_tokens = M.count_messages_tokens(messages)
    local tool_tokens = 0
    if tools then
        tool_tokens = _tools_tokens
    end
    return msg_tokens + tool_tokens
end

-- Aliases for 1-1 parity with Python
M.cache_message = M.count_message_tokens
M.estimate_messages = M.count_messages_tokens
M.set_tool_tokens = M.set_tools_tokens

return M
