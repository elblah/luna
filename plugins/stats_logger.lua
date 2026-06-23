-- Stats Logger Plugin for Luna
-- Logs each AI API request to:
--   - .aicoder/stats.log (local, per-project)
--   - stats_server via Unix socket (for central aggregation)
-- Format: JSONL (one JSON object per line)

local M = {}

local log = require("utils.log")
local json = require("utils.json")
local datetime = require("utils.datetime_utils")
local temp_utils = require("utils.temp_file_utils")

local SOCKET_PATH = temp_utils.get_temp_dir() .. "/stats_server.sock"

-- Generate session ID once per session
local session_id = nil

local function get_session_id()
    if not session_id then
        -- Use a simple unique ID based on time and random
        session_id = string.format("%s-%04d", 
            os.date("%Y%m%d%H%M%S"), 
            math.random(1000, 9999))
    end
    return session_id
end

local function write_to_central(line)
    -- Write to stats_server via Unix socket using nc
    local tmp_file = temp_utils.create_temp_file("luna_stats")
    local f = io.open(tmp_file, "w")
    if not f then return false end
    f:write(line)
    f:close()

    -- Use nc (netcat) to send to Unix socket
    local cmd = string.format(
        "cat %s | nc -q 1 -U %s 2>/dev/null; rm -f %s",
        tmp_file, SOCKET_PATH, tmp_file
    )
    local handle = io.popen(cmd)
    if handle then
        local response = handle:read("*a")
        handle:close()
        if response and response:match("^ok") then
            return true
        end
    end
    -- Socket doesn't exist or write failed - cleanup
    os.remove(tmp_file)
    return false
end

local function log_usage(usage)
    -- Log usage data to local file and central server
    local stats = M._app and M._app.stats
    if not stats then
        return
    end

    -- Get environment info
    local pwd_h = io.popen("pwd")
    local cwd = pwd_h and pwd_h:read("*a"):gsub("%s+$", "") or ""
    if pwd_h then pwd_h:close() end
    local base_url = os.getenv("API_ENDPOINT") or ""
    -- Detect provider from URL
    local api_provider = os.getenv("API_PROVIDER")
    if not api_provider then
        if base_url:match("anthropic") then
            api_provider = "anthropic"
        else
            api_provider = "openai"
        end
    end
    local model = stats.last_model or os.getenv("MODEL") or "unknown"
    local base_url = os.getenv("API_ENDPOINT") or ""
    local elapsed = datetime.round_time(stats.last_api_time or 0)
    local timestamp = datetime.get_stats_timestamp()

    -- Build JSONL entry
    local entry = {
        ts = timestamp,
        session = get_session_id(),
        cwd = cwd,
        api_provider = api_provider,
        url = base_url,
        model = model,
        elapsed = elapsed,
        usage = usage,
    }

    -- Add optional tag
    local tag = os.getenv("STATS_TAG")
    if tag and tag ~= "" then
        entry.tag = tag
    end

    -- cjson escapes / as \/, remove those for Python compatibility
    local json_line = json.encode(entry)

    -- Ensure .aicoder dir exists
    local aicoder_dir = cwd .. "/.aicoder"
    local mkdir_cmd = "mkdir -p " .. aicoder_dir
    io.popen(mkdir_cmd):close()

    -- Append to local stats.log
    local log_path = aicoder_dir .. "/stats.log"
    local f = io.open(log_path, "a")
    if f then
        f:write(json_line .. "\n")
        f:close()
    end

    -- Send to central server
    local ok = write_to_central(json_line .. "\n")
    if not ok then
        -- Silent fail if central server not running
    end
end

function M.create_plugin(ctx)
    log.debug("[stats_logger] Plugin loaded!")
    M._app = ctx.app

    -- Register hook for usage data (fires for ALL API calls including compaction)
    ctx:register_hook("after_usage_data", function(usage)
        log.debug("[stats_logger] after_usage_data hook fired!")
        log_usage(usage)
    end)

    return {}
end

return M.create_plugin
