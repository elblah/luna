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
local exec = require("utils.exec_utils")
local file_utils = require("utils.file_utils")

-- Socket path must use $TMP env var to match Python/C stats_server.
-- Luna runs in a sandbox where /tmp != $TMP, so get_temp_dir() won't work.
-- If $TMP is not set (e.g. Android/Termux), central server is disabled.
local SOCKET_PATH
local _central_available = false
local tmp_val = os.getenv("TMP")
if tmp_val then
    SOCKET_PATH = tmp_val .. "/stats_server.sock"
    _central_available = true
end

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
    if not _central_available then return true end
    -- Write data to temp file first
    local tmp_file = temp_utils.create_temp_file("luna_stats")
    local f = io.open(tmp_file, "w")
    if not f then return false end
    f:write(line)
    f:close()

    -- Use exec.exec() (same as run_shell_command.lua) for reliable timeout + error capture.
    -- Pattern: test socket with nc -z, then pipe data. Fail marker on any error.
    -- Socket path must match what stats_server uses: os.getenv("TMP") or "/tmp"
    local cmd = string.format(
        "timeout -k 0.1s 0.2s nc -z -U %s 2>/dev/null && cat %s | nc -q 1 -U %s 2>/dev/null || echo '__STATS_FAIL__'",
        SOCKET_PATH, tmp_file, SOCKET_PATH
    )
    local result = exec.exec(cmd, 5, nil, {tty = false})

    -- Cleanup temp file
    os.remove(tmp_file)

    if result.stdout and result.stdout:match("__STATS_FAIL__") then
        io.stderr:write(("\n[stats_logger] central server not available, stats not sent:\n  %s\n"):format(line:gsub("%s+$", "")))
        io.stderr:flush()
        return false
    end

    return true
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
    local cfg = require("core.config")
    local base_url = cfg.base_url()
    if base_url == "" then
        base_url = cfg.api_endpoint()
    end
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
        origin = "luna",
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
    file_utils.mkdir_p(aicoder_dir)

    -- Append to local stats.log
    local log_path = aicoder_dir .. "/stats.log"
    local f = io.open(log_path, "a")
    if f then
        f:write(json_line .. "\n")
        f:close()
    end

    -- Send to central server
    write_to_central(json_line .. "\n")
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
