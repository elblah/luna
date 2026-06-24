-- Configuration module for Luna (Lua AICoder)
-- 1-1 port of Python config.py

local M = {}

-- Class-style alias for 1-1 parity with Python's Config class
M.Config = M

-- Version constant (parity with Python's __version__ in __init__.py)
M.__version__ = "1.0.0"

-- ANSI Colors for terminal output
M.colors = {
    reset = "\x1b[0m",
    bold = "\x1b[1m",
    dim = "\x1b[2m",
    black = "\x1b[30m",
    red = "\x1b[31m",
    green = "\x1b[32m",
    yellow = "\x1b[33m",
    blue = "\x1b[34m",
    magenta = "\x1b[35m",
    cyan = "\x1b[36m",
    white = "\x1b[37m",
    brightGreen = "\x1b[92m",
    brightRed = "\x1b[91m",
    brightYellow = "\x1b[93m",
    brightBlue = "\x1b[94m",
    brightMagenta = "\x1b[95m",
    brightCyan = "\x1b[96m",
    brightWhite = "\x1b[97m",
}

-- YOLO mode - initialize from env var ONCE at module load time
M._yolo_mode = os.getenv("YOLO_MODE") == "1"

-- Reasoning format registry (easily extensible)
-- Maps provider format names to their specific settings
M._reasoning_formats = {
    openai = {
        effort_field = "reasoning_effort",  -- top-level, no extra_body
    },
    deepseek = {
        effort_field = "reasoning_effort",  -- snake_case
        uses_extra_body = true,
    },
    glm = {
        effort_field = "reasoningEffort",  -- camelCase
        uses_extra_body = true,
    },
    openrouter = {
        effort_field = "reasoning_effort",
        uses_extra_body = true,
    },
}

-- Model name patterns for auto-detection
M._reasoning_format_patterns = {
    openai = {"gpt", "o1", "o3", "o4", "openai"},
    deepseek = {"deepseek"},
    glm = {"glm", "zhipuai", "z.ai"},
    openrouter = {"openrouter"},
}

function M.get_reasoning_format()
    local env_format = os.getenv("REASONING_FORMAT")
    if env_format then return env_format end
    
    local model = M.model()
    if not model then return nil end
    model = model:lower()
    for format, patterns in pairs(M._reasoning_format_patterns) do
        for _, p in ipairs(patterns) do
            if model:find(p) then return format end
        end
    end
    return nil
end

function M.get_effort_field()
    local fmt = M.get_reasoning_format()
    if fmt and M._reasoning_formats[fmt] then
        return M._reasoning_formats[fmt].effort_field
    end
    return "reasoning_effort"  -- default
end

function M.context_compact_percentage()
    local val = os.getenv("CONTEXT_COMPACT_PERCENTAGE")
    return val and tonumber(val) or 0
end

function M.compact_prune_threshold()
    -- Try pruning if context exceeds this percentage (before full compaction)
    local val = os.getenv("COMPACT_PRUNE_THRESHOLD")
    return val and tonumber(val) or 80
end

function M.yolo_mode()
    return M._yolo_mode
end

function M.get_yolo_mode()
    return M._yolo_mode
end

function M.set_yolo_mode(enabled)
    M._yolo_mode = enabled
end

-- Sandbox disabled - initialize from env var ONCE at module load time
M._sandbox_disabled = os.getenv("MINI_SANDBOX") == "0"

function M.sandbox_disabled()
    return M._sandbox_disabled
end

function M.set_sandbox_disabled(disabled)
    M._sandbox_disabled = disabled
end

-- Detail mode - initialize from env var ONCE at module load time
M._detail_mode = os.getenv("DETAIL") == "1"

function M.detail_mode()
    return M._detail_mode
end

function M.get_detail_mode()
    return M._detail_mode
end

function M.set_detail_mode(enabled)
    M._detail_mode = enabled
end

-- Thinking mode - initialize from env var ONCE at module load time
local function init_thinking()
    local env_val = (os.getenv("THINKING") or ""):lower()
    if env_val == "on" or env_val == "1" or env_val == "yes" or env_val == "true" then
        return "on"
    elseif env_val == "off" or env_val == "0" or env_val == "no" or env_val == "false" then
        return "off"
    end
    return "default"
end

M._thinking = init_thinking()

function M.thinking()
    return M._thinking
end

function M.set_thinking(mode)
    M._thinking = mode
end

-- Clear thinking - initialize from env var ONCE at module load time
local function init_clear_thinking()
    local env_val = (os.getenv("CLEAR_THINKING") or ""):lower()
    if env_val == "1" or env_val == "true" or env_val == "yes" or env_val == "on" then
        return true
    elseif env_val == "0" or env_val == "false" or env_val == "no" or env_val == "off" then
        return false
    end
    return nil
end

M._clear_thinking = init_clear_thinking()

function M.clear_thinking()
    return M._clear_thinking
end

function M.set_clear_thinking(value)
    M._clear_thinking = value
end

-- Suppress error body - initialize from env var ONCE at module load time
local env_suppress = os.getenv("AICODER_SUPPRESS_ERROR_BODY") or ""
M._suppress_error_body = env_suppress == "1" or env_suppress == "true" or env_suppress == "yes" or env_suppress == "on"

function M.suppress_error_body()
    return M._suppress_error_body
end

-- Reasoning effort - initialize from env var ONCE at module load time
M._reasoning_effort = os.getenv("REASONING_EFFORT") or nil

function M.reasoning_effort()
    return M._reasoning_effort
end

function M.set_reasoning_effort(effort)
    M._reasoning_effort = effort
end

-- Temp directory for exec_utils (isolated per instance)
M.tmp_dir = nil

function M.set_tmp_dir(dir)
    M.tmp_dir = dir
end

function M.get_tmp_dir()
    return M.tmp_dir
end

function M._get_valid_reasoning_efforts()
    local env_val = os.getenv("REASONING_EFFORT_VALID") or ""
    if env_val == "" then
        return nil
    end
    local valid = {}
    for v in env_val:gmatch("[^,]+") do
        valid[v:trim():lower()] = true
    end
    return valid
end

-- Retry Configuration
M._runtime_max_retries = nil
M._runtime_max_backoff = nil

function M.max_retries()
    local val = os.getenv("MAX_RETRIES") or "10"
    return tonumber(val) or 10
end

function M.effective_max_retries()
    if M._runtime_max_retries ~= nil then
        return M._runtime_max_retries
    end
    return M.max_retries()
end

function M.set_runtime_max_retries(value)
    M._runtime_max_retries = value
end

function M.max_backoff()
    local val = os.getenv("MAX_BACKOFF_SECONDS") or "64"
    return tonumber(val) or 64
end

function M.effective_max_backoff()
    if M._runtime_max_backoff ~= nil then
        return M._runtime_max_backoff
    end
    return M.max_backoff()
end

function M.set_runtime_max_backoff(value)
    M._runtime_max_backoff = value
end

-- API Configuration
function M.api_key()
    return os.getenv("OPENAI_API_KEY") or os.getenv("API_KEY") or ""
end

function M.base_url()
    return os.getenv("OPENAI_BASE_URL") or os.getenv("API_BASE_URL") or ""
end

function M.api_endpoint()
    local override = os.getenv("API_ENDPOINT")
    if override then
        return override
    end
    local base = M.base_url()
    if base ~= "" then
        -- Strip trailing /v1 if present to avoid double path
        base = base:gsub("/v1$", "")
        return base .. "/v1/chat/completions"
    end
    -- No default - let it be empty so streaming client doesn't make invalid requests
    return ""
end

function M.model()
    local model = os.getenv("OPENAI_MODEL") or os.getenv("API_MODEL") or ""
    -- Only use env var, don't fallback to hardcoded model
    return model
end

function M.system_prompt()
    return os.getenv("AICODER_SYSTEM_PROMPT") or ""
end

function M.system_prompt_append()
    return os.getenv("AICODER_SYSTEM_PROMPT_APPEND") or ""
end

function M.tools_allow()
    local env_val = os.getenv("TOOLS_ALLOW") or ""
    env_val = env_val:match("^%s*(.*%S)") or env_val
    if env_val ~= "" then
        local tools = {}
        for name in env_val:gmatch("[^,]+") do
            local trimmed = name:match("^%s*(.*%S)")
            if trimmed then
                tools[trimmed] = true
            end
        end
        return tools
    end
    return nil
end

function M.tools_deny()
    local env_val = os.getenv("TOOLS_DENY") or ""
    env_val = env_val:match("^%s*(.*%S)") or env_val
    if env_val ~= "" then
        local tools = {}
        for name in env_val:gmatch("[^,]+") do
            local trimmed = name:match("^%s*(.*%S)")
            if trimmed then
                tools[trimmed] = true
            end
        end
        return tools
    end
    return {}
end

function M.plugins_allow()
    local env_val = os.getenv("PLUGINS_ALLOW") or ""
    env_val = env_val:match("^%s*(.*%S)") or env_val
    if env_val ~= "" then
        local plugins = {}
        for name in env_val:gmatch("[^,]+") do
            local trimmed = name:match("^%s*(.*%S)")
            if trimmed then
                plugins[trimmed] = true
            end
        end
        return plugins
    end
    return nil
end

function M.plugins_deny()
    local env_val = os.getenv("PLUGINS_DENY") or ""
    env_val = env_val:match("^%s*(.*%S)") or env_val
    if env_val ~= "" then
        local plugins = {}
        for name in env_val:gmatch("[^,]+") do
            local trimmed = name:match("^%s*(.*%S)")
            if trimmed then
                plugins[trimmed] = true
            end
        end
        return plugins
    end
    return {}
end

function M.http_headers()
    local headers_str = os.getenv("AICODER_HTTP_HEADERS") or ""
    if headers_str == "" then
        return {}
    end
    local headers = {}
    for pair in headers_str:gmatch("[^;]+") do
        local key, val = pair:match("^%s*(%S+)%s*:%s*(.*)")
        if key and val then
            headers[key] = val
        end
    end
    return headers
end

function M.user_agent()
    return os.getenv("USER_AGENT") or os.getenv("AICODER_USER_AGENT") or nil
end

function M.streaming_enabled()
    return os.getenv("AICODER_STREAM") ~= "0"
end

function M.temperature()
    local temp = os.getenv("TEMPERATURE")
    if temp then
        return tonumber(temp)
    end
    return nil
end

function M.max_tokens()
    local max_tokens = os.getenv("MAX_TOKENS")
    if max_tokens then
        return tonumber(max_tokens)
    end
    return nil
end

function M.stop()
    return nil
end

function M.custom_headers()
    return nil
end

function M.top_p()
    local top_p = os.getenv("TOP_P")
    if top_p then
        return tonumber(top_p)
    end
    return nil
end

function M.frequency_penalty()
    local freq_penalty = os.getenv("FREQUENCY_PENALTY")
    if freq_penalty then
        return tonumber(freq_penalty)
    end
    return nil
end

function M.presence_penalty()
    local pres_penalty = os.getenv("PRESENCE_PENALTY")
    if pres_penalty then
        return tonumber(pres_penalty)
    end
    return nil
end

function M.top_k()
    local top_k = os.getenv("TOP_K")
    if top_k then
        return tonumber(top_k)
    end
    return nil
end

function M.repetition_penalty()
    local rep_penalty = os.getenv("REPETITION_PENALTY")
    if rep_penalty then
        return tonumber(rep_penalty)
    end
    return nil
end

function M.total_timeout()
    local val = os.getenv("TOTAL_TIMEOUT") or "300"
    return tonumber(val) or 300
end

function M.total_timeout_extension()
    local val = os.getenv("TOTAL_TIMEOUT_EXTENSION") or "30"
    return tonumber(val) or 30
end

function M.context_size()
    -- Use runtime value if set, otherwise env var
    if M._context_size then
        return M._context_size
    end
    local val = os.getenv("CONTEXT_SIZE") or "128000"
    return tonumber(val) or 128000
end

function M.set_context_size(size)
    M._context_size = size
end

-- context_compact_percentage() is defined at module load time above

function M.auto_compact_threshold()
    local percentage = M.context_compact_percentage()
    if percentage > 0 then
        local capped_percentage = math.min(percentage, 100)
        return math.floor(M.context_size() * (capped_percentage / 100))
    end
    return 0
end

function M.auto_compact_enabled()
    return M.auto_compact_threshold() > 0
end

function M.tmux_prune_percentage()
    local val = os.getenv("TMUX_PRUNE_PERCENTAGE") or "50"
    return tonumber(val) or 50
end

function M.compact_protect_rounds()
    local val = os.getenv("COMPACT_PROTECT_ROUNDS") or "2"
    return tonumber(val) or 2
end

function M.min_summary_length()
    local val = os.getenv("MIN_SUMMARY_LENGTH") or "100"
    return tonumber(val) or 100
end

function M.force_compact_size()
    local val = os.getenv("FORCE_COMPACT_SIZE") or "5"
    return tonumber(val) or 5
end

function M.max_tool_result_size()
    local val = os.getenv("MAX_TOOL_RESULT_SIZE") or "20000"
    return tonumber(val) or 20000
end

function M.default_read_limit()
    local val = os.getenv("DEFAULT_READ_LIMIT") or "150"
    return tonumber(val) or 150
end

function M.default_grep_max_results()
    local val = os.getenv("DEFAULT_GREP_MAX_RESULTS") or "500"
    return tonumber(val) or 500
end

function M.default_shell_timeout()
    local val = os.getenv("DEFAULT_SHELL_TIMEOUT") or "30"
    return tonumber(val) or 30
end

-- Debug mode
M._debug_enabled = os.getenv("DEBUG") == "1"

function M.debug()
    return M._debug_enabled
end

function M.set_debug(enabled)
    M._debug_enabled = enabled
end

-- Thinking extra body (for extra_body parameter)
-- Returns nil if format doesn't use extra_body (e.g., OpenAI)
function M.thinking_extra_body()
    local fmt = M.get_reasoning_format()
    if fmt and M._reasoning_formats[fmt] then
        if not M._reasoning_formats[fmt].uses_extra_body then
            return nil  -- OpenAI doesn't use extra_body for thinking
        end
    end
    
    local mode = M.thinking()
    if mode == "default" then
        return nil
    elseif mode == "off" then
        return {thinking = {type = "disabled"}}
    elseif mode == "on" then
        return {thinking = {type = "enabled"}}
    end
    return nil
end

-- Thinking parameters for top-level (like reasoning_effort for DeepSeek)
function M.thinking_params()
    local mode = M.thinking()
    if mode == "on" then
        local params = {}
        local effort = M.reasoning_effort()
        if effort then
            local field = M.get_effort_field()
            params[field] = effort
        end
        local clear_thinking = M.clear_thinking()
        if clear_thinking ~= nil then
            params.clear_thinking = clear_thinking
        end
        if next(params) then
            return params
        end
    end
    return nil
end

-- Default ignore directories
M.DEFAULT_IGNORE_DIRS = {
    '.git',
    '__pycache__',
    '.ruff_cache',
    '.pytest_cache',
    '.aicoder',
    'node_modules',
    '.egg-info',
    '.dist-info',
    '.tox',
    '.venv',
    'venv',
    '.mypy_cache',
}

function M.ignore_dirs()
    local env_value = os.getenv('AICODER_IGNORE_DIRS') or ''
    if env_value == '' then
        return M.DEFAULT_IGNORE_DIRS
    end
    local dirs = {}
    for dir in env_value:gmatch("[^,]+") do
        local trimmed = dir:match("^%s*(.*%S)")
        if trimmed then
            table.insert(dirs, trimmed)
        end
    end
    return dirs
end

function M.ignore_patterns()
    local env_value = os.getenv('AICODER_IGNORE_PATTERNS') or ''
    if env_value == '' then
        return {".pyc", ".pyo", ".so", ".a", ".o"}
    end
    local patterns = {}
    for pattern in env_value:gmatch("[^,]+") do
        local trimmed = pattern:match("^%s*(.*%S)")
        if trimmed then
            table.insert(patterns, trimmed)
        end
    end
    return patterns
end

function M.session_dir()
    return os.getenv("AICODER_SESSION_DIR") or ".aicoder"
end
-- No fallbacks - use only configured provider
function M.fallback_configs()
    return {}
end

function M.validate_config()
    local api_provider = os.getenv("API_PROVIDER") or ""
    api_provider = api_provider:lower()
    
    local api_endpoint = os.getenv("API_ENDPOINT") or ""
    
    -- Auto-detect anthropic from endpoint URL
    if api_endpoint ~= "" and (api_endpoint:find("anthropic") or api_endpoint:find("claude")) then
        api_provider = "anthropic"
    end
    
    if api_provider == "anthropic" then
        if not os.getenv("API_ENDPOINT") then
            print("[!] Error: Missing required environment variable:")
            print("[!]   - API_ENDPOINT")
            print("")
            print("[*] Example configuration:")
            print('[+]   export API_PROVIDER=anthropic')
            print('[+]   export API_ENDPOINT="https://api.minimax.io/anthropic/v1/messages"')
            print("")
            print("Optional variables:")
            print('[+]   export API_KEY="your-api-key-here"')
            print('[+]   export API_MODEL="your-model-name"')
            print("[*]   export DEBUG=1")
            os.exit(1)
        end
    elseif M.base_url() == "" then
        print("[!] Error: Missing required environment variable:")
        print("[!]   - API_BASE_URL or OPENAI_BASE_URL")
        print("")
        print("[*] Example configuration:")
        print('[+]   export API_BASE_URL="https://your-api-provider.com/v1"')
        print("")
        print("Optional variables:")
        print('[+]   export API_KEY="your-api-key-here" (optional, some providers don\'t require it)')
        print('[+]   export API_MODEL="your-model-name" (optional, some providers have a default)')
        print("[*]   export TEMPERATURE=0.0")
        print("[*]   export MAX_TOKENS=4096")
        print("[*]   export DEBUG=1")
        print('[+]   export AICODER_SYSTEM_PROMPT="your-custom-prompt"')
        print('[+]   export AICODER_SYSTEM_PROMPT_APPEND="additional-instructions"')
        print("")
        print("Anthropic Provider:")
        print("    export API_PROVIDER=anthropic")
        print("    export API_ENDPOINT=\"https://api.minimax.io/anthropic/v1/messages\"")
        os.exit(1)
    end
end

function M.print_startup_info()
    -- Match v3's Configuration output
    local log = require("utils.log")
    
    log.success("Configuration:")
    
    -- API Provider (show only if explicitly set)
    local api_provider = os.getenv("API_PROVIDER") or ""
    if api_provider ~= "" then
        log.success("  API Provider: " .. api_provider)
    end
    
    log.success("  API Endpoint: " .. M.api_endpoint())
    log.success("  Model: " .. M.model())
    
    if M.debug() then
        log.warn("DEBUG MODE IS ON")
    end
    
    -- Thinking mode
    local mode = M.thinking()
    if mode ~= "default" then
        local mode_text = "  Thinking: " .. mode
        if mode == "on" then
            local effort = M.reasoning_effort()
            if effort then
                mode_text = mode_text .. " (effort: " .. effort .. ")"
            end
            local fmt = M.get_reasoning_format()
            local fmt_override = os.getenv("REASONING_FORMAT")
            if fmt then
                if fmt_override then
                    mode_text = mode_text .. " (format: " .. fmt .. ", override)"
                else
                    mode_text = mode_text .. " (format: " .. fmt .. ")"
                end
            end
        end
        log.success(mode_text)
    end
    
    if os.getenv("TEMPERATURE") then
        log.success("  Temperature: " .. tostring(M.temperature()))
    end
    
    if os.getenv("MAX_TOKENS") then
        log.success("  Max tokens: " .. tostring(M.max_tokens()))
    end
    
    if M.system_prompt() ~= "" then
        log.success("  System prompt: overridden via AICODER_SYSTEM_PROMPT environment variable")
    end
    
    if M.system_prompt_append() ~= "" then
        log.success("  System prompt append: set via AICODER_SYSTEM_PROMPT_APPEND environment variable")
    end
    
    if M.auto_compact_enabled() then
        log.success("  Auto-compaction enabled (context: " .. M.context_size() .. " tokens, triggers at " .. M.context_compact_percentage() .. "%)")
    else
        log.note("  Auto-compaction disabled (set CONTEXT_COMPACT_PERCENTAGE to enable)")
    end
end

function M.reset()
    -- Reset all runtime state to defaults
    M._yolo_mode = os.getenv("YOLO_MODE") == "1"
    M._sandbox_disabled = os.getenv("MINI_SANDBOX") == "0"
    M._detail_mode = os.getenv("DETAIL") == "1"
    M._debug_enabled = os.getenv("DEBUG") == "1"
end

function M.in_tmux()
    return os.getenv("TMUX_PANE") ~= nil
end

function M.socket_only()
    return os.getenv("AICODER_SOCKET_ONLY") == "1"
end

-- Aliases for 1-1 parity with Python (Python uses _init_*_from_env helpers)
M._init_thinking_from_env = init_thinking
M._init_clear_thinking_from_env = init_clear_thinking
function M._init_reasoning_effort_from_env()
    return os.getenv("REASONING_EFFORT") or nil
end

return M