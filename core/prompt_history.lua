-- Prompt History for Luna
-- JSONL format: {"prompt": "..."}
-- Loads/saves from .aicoder/history

local M = {}

local json = require("utils.json")
local log = require("utils.log")

-- Module state
local _HISTORY_PATH = nil
local _MAX_HISTORY_LINES = tonumber(os.getenv("AICODER_HISTORY_MAX")) or 30
local _SAVE_COUNT = 0
local _TRUNCATE_INTERVAL = 10  -- truncate every 10 saves

-- Lazy init - called on first use, not at require time
local function _ensure_history_dir()
    if _HISTORY_PATH then return _HISTORY_PATH end
    local aicoder_dir = ".aicoder"
    local history_path = aicoder_dir .. "/history"
    
    -- Ensure .aicoder directory exists
    os.execute("mkdir -p " .. aicoder_dir .. " 2>/dev/null")
    
    _HISTORY_PATH = history_path
    return _HISTORY_PATH
end

-- Truncate history file to keep only last N lines
function M._truncate_if_needed(path)
    local file, err = io.open(path, "r")
    if not file then return end
    
    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()
    
    if #lines <= _MAX_HISTORY_LINES then return end
    
    -- Keep only last N lines
    local trimmed = {}
    local start = #lines - _MAX_HISTORY_LINES + 1
    for i = start, #lines do
        table.insert(trimmed, lines[i])
    end
    
    local out, err = io.open(path, "w")
    if not out then return end
    out:write(table.concat(trimmed, "\n") .. "\n")
    out:close()
end

function M.save_prompt(prompt)
    -- Skip empty prompts, commands (start with /), and Y/n approval responses
    if not prompt or prompt:match("^%s*$") or prompt:match("^/") or prompt:match("^[Yn]$") then
        return
    end
    
    local path = _ensure_history_dir()
    
    local entry = {prompt = prompt}
    local line = json.encode(entry) .. "\n"
    
    local file, err = io.open(path, "a")
    if not file then
        return
    end
    
    file:write(line)
    file:close()
    
    -- Truncate on first save or every N saves
    _SAVE_COUNT = _SAVE_COUNT + 1
    if _SAVE_COUNT == 1 or _SAVE_COUNT % _TRUNCATE_INTERVAL == 0 then
        M._truncate_if_needed(path)
    end
end

function M.read_history()
    local path = _ensure_history_dir()
    
    local file, err = io.open(path, "r")
    if not file then
        return {}
    end
    
    local content = file:read("*all")
    file:close()
    
    if not content or content == "" then
        return {}
    end
    
    local result = {}
    for line in content:gmatch("[^\n]+") do
        if line and line ~= "" then
            local ok, entry = pcall(json.decode, line)
            if ok and entry and entry.prompt and entry.prompt ~= "" then
                table.insert(result, {prompt = entry.prompt})
            end
        end
    end
    
    return result
end

return M
