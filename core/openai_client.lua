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

-- Send request to OpenAI-compatible API.
-- Returns {ok=true, content, tool_calls, finish_reason, usage, [reasoning_field]=reasoning}
-- When config.streaming_enabled() is true, uses SSE streaming internally to capture
-- reasoning content that some APIs only send in streaming mode.
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
    
    -- Route to streaming or sync based on config
    local response
    if config.streaming_enabled() then
        response = self:_send_request_stream(request_data, headers, endpoint, start_time)
    else
        response = self:_send_request_sync(request_data, headers, endpoint, start_time)
    end
    
    -- Debug: save last request after streaming path may have modified request_data (e.g., stream=true)
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
    
    return response
end

-- Non-streaming path: send request, parse full JSON response
function OpenAIClient:_send_request_sync(request_data, headers, endpoint, start_time)
    local model = request_data.model
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
    self:_update_stats(start_time, model, data.usage)
    
    -- Call plugin hook for usage data
    if data.usage and self._plugin_system then
        self._plugin_system:call_hooks("after_usage_data", data.usage)
    end
    
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
    
    -- Debug: save last response
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

-- Streaming path: uses SSE to accumulate content + reasoning, returns same shape
function OpenAIClient:_send_request_stream(request_data, headers, endpoint, start_time)
    request_data.stream = true
    
    local body = json.encode(request_data)
    local timeout = config.total_timeout() or 300
    
    local content = ""
    local reasoning_content = ""
    local reasoning_field = nil
    local tool_calls = nil
    local finish_reason = nil
    local usage = nil
    local api_error = nil
    
    -- Collect raw SSE lines for debug log
    local sse_lines = nil
    if config.debug() then
        sse_lines = {}
    end
    
    local ok, err = http_utils.fetch_stream(endpoint, {
        method = "POST",
        headers = headers,
        body = body,
        timeout = timeout,
    }, function(line)
        -- Collect raw SSE lines for debug
        if sse_lines then
            table.insert(sse_lines, line)
        end
        
        if line == "" then return end
        
        -- SSE data line
        if line:match("^data: ") then
            local json_data = line:sub(7)
            if json_data == "[DONE]" then return end
            
            local ok, chunk = pcall(json.decode, json_data)
            if not ok or not chunk then return end
            
            -- Check for error in stream
            if chunk.error then
                api_error = chunk.error.message or chunk.error.code or tostring(chunk.error)
                return
            end
            
            -- Capture usage (usually in last chunk)
            if chunk.usage then
                usage = chunk.usage
            end
            
            if chunk.choices and #chunk.choices > 0 then
                local choice = chunk.choices[1]
                if choice.finish_reason then
                    finish_reason = choice.finish_reason
                end
                
                local delta = choice.delta
                if delta then
                    -- Accumulate content
                    if delta.content then
                        content = content .. delta.content
                    end
                    
                    -- Accumulate reasoning (check multiple field names)
                    local reasoning_fields = {"reasoning_content", "reasoning", "thinking", "reasoning_text"}
                    local override = config.get_reasoning_field()
                    if override then
                        table.insert(reasoning_fields, 1, override)
                    end
                    for _, field in ipairs(reasoning_fields) do
                        if delta[field] and delta[field] ~= "" then
                            reasoning_content = reasoning_content .. delta[field]
                            if not reasoning_field then
                                reasoning_field = field
                            end
                            break
                        end
                    end
                    
                    -- Accumulate tool calls (index-based from streaming delta)
                    if delta.tool_calls then
                        if not tool_calls then
                            tool_calls = {}
                        end
                        for _, tc_delta in ipairs(delta.tool_calls) do
                            local idx = (tc_delta.index or 0) + 1
                            if not tool_calls[idx] then
                                tool_calls[idx] = {
                                    id = tc_delta.id or "",
                                    type = tc_delta.type or "function",
                                    ["function"] = {name = "", arguments = ""}
                                }
                            end
                            local tc = tool_calls[idx]
                            if tc_delta.id then tc.id = tc_delta.id end
                            if tc_delta.type then tc.type = tc_delta.type end
                            if tc_delta["function"] then
                                if tc_delta["function"].name then
                                    tc["function"].name = tc_delta["function"].name
                                end
                                if tc_delta["function"].arguments then
                                    tc["function"].arguments = tc["function"].arguments .. tc_delta["function"].arguments
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    
    if not ok then
        return {ok = false, status = 0, error = err or "Stream request failed"}
    end
    
    if api_error then
        return {ok = false, status = 0, error = api_error}
    end
    
    -- Update stats
    self:_update_stats(start_time, request_data.model, usage)
    
    if usage and self._plugin_system then
        self._plugin_system:call_hooks("after_usage_data", usage)
    end
    
    local result = {
        ok = true,
        content = content,
        tool_calls = tool_calls and #tool_calls > 0 and tool_calls or nil,
        finish_reason = finish_reason,
        usage = usage,
    }
    
    if reasoning_content ~= "" and reasoning_field then
        result[reasoning_field] = reasoning_content
    end
    
    -- Write raw SSE log for debugging
    if sse_lines then
        pcall(function()
            local dir = ".aicoder"
            os.execute("mkdir -p " .. dir)
            local f = io.open(dir .. "/last-response-sse.log", "w")
            if f then
                f:write(table.concat(sse_lines, "\n"))
                f:write("\n")
                f:close()
            end
        end)
    end
    
    return result
end

-- Shared stats update
function OpenAIClient:_update_stats(start_time, model, usage)
    local elapsed = datetime.get_time() - start_time
    if self.stats then
        self.stats:add_api_time(elapsed)
        self.stats:set_last_model(model)
        if usage then
            self.stats:add_tokens(usage.prompt_tokens or 0, usage.completion_tokens or 0)
            self.stats:add_usage_info(usage)
        end
    end
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
