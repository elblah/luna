-- OpenAI-compatible API client for Luna (non-streaming)
-- Supports Pollinations AI and other OpenAI-compatible APIs

local config = require("core.config")
local http_utils = require("utils.http_utils")
local json = require("utils.json")
local datetime = require("utils.datetime_utils")
local log = require("utils.log")

local OpenAIClient = {}
OpenAIClient.__index = OpenAIClient

function OpenAIClient.new(stats, tool_manager, message_history)
    local self = setmetatable({}, OpenAIClient)
    self.stats = stats or nil
    self.tool_manager = tool_manager or nil
    self.message_history = message_history or nil
    self._plugin_system = nil
    return self
end

function OpenAIClient:set_plugin_system(plugin_system)
    self._plugin_system = plugin_system
end

-- Non-streaming request - returns response directly
function OpenAIClient:send_request(request)
    local messages = request.messages or {}
    local model = request.model or config.model()
    local send_tools = request.send_tools

    local start_time = datetime.get_time()
    
    local endpoint = config.api_endpoint()
    if not endpoint or endpoint == "" then
        error("API endpoint not configured. Set API_ENDPOINT environment variable.")
    end
    
    local headers = {
        ["Content-Type"] = "application/json",
    }
    
    -- Add Authorization header if API key is configured
    local api_key = config.api_key()
    if api_key and api_key ~= "" then
        headers["Authorization"] = "Bearer " .. api_key
    end
    
    -- Add custom headers if configured
    local custom_headers = config.http_headers()
    for k, v in pairs(custom_headers) do
        headers[k] = v
    end
    
    -- Add user agent if configured
    if config.user_agent() then
        headers["User-Agent"] = config.user_agent()
    end
    
    -- Debug: force 429 error for testing retry logic
    if os.getenv("DEBUG_FORCE_429") == "1" then
        return {ok = false, status = 429, error = "Queue full for IP"}
    end
    
    local request_data = {
        model = model,
        messages = messages,
    }
    
    -- Add optional parameters
    self:_add_optional_params(request_data)
    
    -- Add tools if requested
    if send_tools and self.tool_manager then
        local tools = self.tool_manager:get_tool_definitions()
        if tools and #tools > 0 then
            request_data.tools = tools
        end
    end
    
    -- Debug: save last request to .aicoder/last-request.json (relative to cwd)
    if config.debug() then
        pcall(function()
            local dir = ".aicoder"
            os.execute("mkdir -p " .. dir)
            local f = io.open(dir .. "/last-request.json", "w")
            if f then
                f:write(json.encode(request_data))
                f:close()
            end
        end)
    end
    
    local body = json.encode(request_data)
    local timeout = config.total_timeout() or 300
    
    local response = http_utils.fetch(endpoint, {
        method = "POST",
        headers = headers,
        body = body,
        timeout = timeout,
    })
    
    if not response.ok then
        local error_msg = response.body
        if response.status == 0 then
            error_msg = "Request cancelled or network error"
        end
        return {ok = false, status = response.status, error = error_msg}
    end
    
    local data = response:json()
    if not data then
        return {ok = false, status = response.status, error = "Failed to parse JSON"}
    end
    
    if data.error then
        local err_msg = data.error.message or data.error.code or tostring(data.error)
        return {ok = false, status = response.status, error = err_msg}
    end
    
    -- Extract content and reasoning from response
    -- Different providers use different field names for reasoning:
    -- - Pollinations: "reasoning"
    -- - OpenAI-compatible: "reasoning_content"
    -- - Some use "thinking" or "reasoning_text"
    local content = ""
    local tool_calls = nil
    local reasoning_content = ""
    local reasoning_field = nil
    
    if data.choices and #data.choices > 0 then
        local choice = data.choices[1]
        if choice.message then
            content = choice.message.content or ""
            tool_calls = choice.message.tool_calls
            
            -- Check various reasoning field names
            local reasoning_fields = {"reasoning_content", "reasoning", "thinking", "reasoning_text"}
            -- Prepend env var override if set
            local override = config.get_reasoning_field()
            if override then
                table.insert(reasoning_fields, 1, override)
            end
            for _, field in ipairs(reasoning_fields) do
                if choice.message[field] and choice.message[field] ~= "" then
                    reasoning_content = choice.message[field]
                    reasoning_field = field
                    break
                end
            end
        end
    end
    
    -- Update stats
    local elapsed = datetime.get_time() - start_time
    if self.stats then
        self.stats:add_api_time(elapsed)
        self.stats:set_last_model(model)
        if data.usage then
            self.stats:add_tokens(
                data.usage.prompt_tokens or 0,
                data.usage.completion_tokens or 0
            )
            self.stats:add_usage_info(data.usage)
        end
    end

    -- Call plugin hook for usage data
    if data.usage and self._plugin_system then
        self._plugin_system:call_hooks("after_usage_data", data.usage)
    end
    
    -- Return response
    local result = {
        ok = true,
        content = content,
        tool_calls = tool_calls,
        finish_reason = data.choices and data.choices[1] and data.choices[1].finish_reason,
        usage = data.usage,
    }
    
    if reasoning_content ~= "" and reasoning_field then
        result[reasoning_field] = reasoning_content
    end
    
    -- Debug: save last response to .aicoder/last-response.json
    if config.debug() then
        pcall(function()
            local dir = ".aicoder"
            os.execute("mkdir -p " .. dir)
            local f = io.open(dir .. "/last-response.json", "w")
            if f then
                f:write(json.encode(data))
                f:close()
            end
        end)
    end
    
    return result
end

function OpenAIClient:_add_optional_params(data)
    local temp = config.temperature()
    if temp then data.temperature = temp end
    
    local max_tok = config.max_tokens()
    if max_tok then data.max_tokens = max_tok end
    
    local top_p = config.top_p()
    if top_p then data.top_p = top_p end
    
    local freq = config.frequency_penalty()
    if freq then data.frequency_penalty = freq end
    
    local pres = config.presence_penalty()
    if pres then data.presence_penalty = pres end
    
    -- Add thinking extra_body if configured
    local thinking_extra = config.thinking_extra_body()
    if thinking_extra then
        for k, v in pairs(thinking_extra) do
            data[k] = v
        end
    end
    
    -- Add top-level thinking params (e.g., reasoning_effort for DeepSeek)
    local thinking_params = config.thinking_params()
    if thinking_params then
        for k, v in pairs(thinking_params) do
            data[k] = v
        end
    end
end

function OpenAIClient:update_token_stats(usage)
    if not usage or not self.stats then return end
    self.stats:add_tokens(
        usage.prompt_tokens or 0,
        usage.completion_tokens or 0
    )
end

return OpenAIClient
