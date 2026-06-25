-- Handles Anthropic-compatible endpoints with content[] block format
-- Non-streaming only

local config = require("core.config")
local json = require("utils.json")

-- Helper function to convert a single assistant message to Anthropic content blocks
local function assistant_to_content_blocks(msg)
    local content_blocks = {}
    
    -- Add thinking block if present (with signature for Anthropic)
    if msg.thinking then
        local thinking_block = {
            type = "thinking",
            thinking = msg.thinking
        }
        if msg.thinking_signature then
            thinking_block.signature = msg.thinking_signature
        end
        table.insert(content_blocks, thinking_block)
    end
    
    -- Add tool_use blocks
    if msg.tool_calls and type(msg.tool_calls) == "table" then
        for _, tc in ipairs(msg.tool_calls) do
            local func = tc["function"] or {}
            local args = func.arguments or "{}"
            if type(args) == "string" then
                local parse_ok, parsed = pcall(json.decode, args)
                if parse_ok then
                    args = parsed
                end
            end
            table.insert(content_blocks, {
                type = "tool_use",
                id = tc.id or "",
                name = func.name or "",
                input = args or {}
            })
        end
    end
    
    -- Add text block if content exists
    if msg.content and type(msg.content) == "string" and msg.content ~= "" then
        table.insert(content_blocks, {
            type = "text",
            text = msg.content
        })
    end
    
    return content_blocks
end

local AnthropicClient = {}
local http_utils = require("utils.http_utils")
local datetime = require("utils.datetime_utils")
local log = require("utils.log")

AnthropicClient.__index = AnthropicClient

function AnthropicClient.new(stats, tool_manager, message_history)
    local self = setmetatable({}, AnthropicClient)
    self.stats = stats or nil
    self.tool_manager = tool_manager or nil
    self.message_history = message_history or nil
    self._plugin_system = nil
    return self
end

function AnthropicClient:set_plugin_system(plugin_system)
    self._plugin_system = plugin_system
end

-- Simple non-streaming request
function AnthropicClient:send_request(request)
    local messages = request.messages or {}
    local model = request.model or config.model()

    local start_time = datetime.get_time()
    
    local endpoint = config.api_endpoint()
    if not endpoint or endpoint == "" then
        error("API endpoint not configured. Set API_ENDPOINT environment variable.")
    end
    
    local headers = self:_build_headers()
    
    -- Debug: force 429 error for testing retry logic
    if os.getenv("DEBUG_FORCE_429") == "1" then
        return {ok = false, status = 429, error = "Queue full for IP"}
    end
    
    -- Separate system messages from conversation messages
    local system_parts = {}
    local conversation_messages = {}
    for _, msg in ipairs(messages) do
        if msg.role == "system" then
            table.insert(system_parts, msg.content or "")
        else
            table.insert(conversation_messages, msg)
        end
    end

    -- Convert non-system messages from OpenAI format to Anthropic format
    local anthropic_messages = self:_convert_messages(conversation_messages)
    
    local request_data = {
        model = model,
        messages = anthropic_messages,
        max_tokens = config.max_tokens() or 8192,
    }
    
    -- Add system as top-level field (Anthropic API spec)
    if #system_parts > 0 then
        request_data.system = table.concat(system_parts, "\n")
    end
    
    self:_add_optional_params(request_data)
    
    -- Add tools if requested (Anthropic format)
    if request.send_tools and self.tool_manager then
        local tools = self.tool_manager:get_tool_definitions()
        if tools and #tools > 0 then
            local anthropic_tools = {}
            for _, tool in ipairs(tools) do
                local func = tool["function"] or {}
                table.insert(anthropic_tools, {
                    name = func.name,
                    description = func.description or "",
                    input_schema = func.parameters or {type = "object", properties = {}}
                })
            end
            request_data.tools = anthropic_tools
        end
    end
    
    -- Debug: save last request to .aicoder/last-request.json (relative to cwd)
    if config.debug() then
        pcall(function()
            local dir = ".aicoder"
            os.execute("mkdir -p " .. dir)
            local filepath = dir .. "/last-request.json"
            local f = io.open(filepath, "w")
            if f then
                f:write(json.encode(request_data))
                f:close()
                log.debug("Saved last-request.json")
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
        return {ok = false, status = response.status, error = data.error.message or "Unknown error"}
    end
    
    -- Extract content from Anthropic format (content[] blocks)
    local content = ""
    local tool_calls = nil
    local thinking = nil
    local thinking_signature = nil
    
    local content_blocks = data.content or {}
    if type(content_blocks) == "table" then
        for _, block in ipairs(content_blocks) do
            local btype = block.type
            
            if btype == "thinking" then
                thinking = block.thinking or ""
                thinking_signature = block.signature or ""
            elseif btype == "text" then
                content = block.text or ""
            elseif btype == "tool_use" then
                local tool_id = block.id or ""
                local tool_name = block.name or ""
                local tool_input = block.input or {}
                local ok, encoded = pcall(json.encode, tool_input)
                if ok then
                    if not tool_calls then tool_calls = {} end
                    table.insert(tool_calls, {
                        id = tool_id,
                        type = "function",
                        ["function"] = {
                            name = tool_name,
                            arguments = encoded
                        }
                    })
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
                data.usage.input_tokens or 0,
                data.usage.output_tokens or 0
            )
            self.stats:add_usage_info(data.usage)
        end
    end

    -- Call plugin hook for usage data
    if data.usage and self._plugin_system then
        self._plugin_system:call_hooks("after_usage_data", data.usage)
    end
    
    -- Build result - preserve thinking with its field name
    local result = {
        ok = true,
        id = data.id,
        model = data.model,
        content = content,
        tool_calls = tool_calls,
        finish_reason = data.stop_reason,
        usage = data.usage,
    }
    if thinking then
        result.thinking = thinking
        if thinking_signature then
            result.thinking_signature = thinking_signature
        end
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

function AnthropicClient:_build_headers()
    local headers = {
        ["Content-Type"] = "application/json",
        ["anthropic-version"] = "2023-06-01",
    }
    
    local api_key = config.api_key()
    if api_key and api_key ~= "" then
        headers["x-api-key"] = api_key
        headers["Authorization"] = "Bearer " .. api_key
    end
    
    local custom_headers = config.http_headers()
    for k, v in pairs(custom_headers) do
        headers[k] = v
    end
    
    return headers
end

function AnthropicClient:_convert_messages(messages)
    local result = {}
    
    for _, msg in ipairs(messages) do
        local role = msg.role
        
        if role == "system" then
            -- Skip - handled as top-level `system` field in send_request
        elseif role == "tool" then
            -- Convert tool result: tool_call_id -> tool_use_id
            table.insert(result, {
                role = "user",
                content = {
                    {
                        type = "tool_result",
                        tool_use_id = msg.tool_call_id or msg.tool_use_id or "",
                        content = msg.content or ""
                    }
                }
            })
        elseif role == "assistant" then
            -- Convert ALL assistant messages to Anthropic format
            -- Check if content is already properly formatted as content blocks
            local content_is_array = type(msg.content) == "table" and msg.content[1] and msg.content[1].type
            
            if content_is_array then
                -- Already formatted, just pass through (but ensure role is correct)
                table.insert(result, msg)
            else
                -- Convert from flat format (thinking/content at top level) to content blocks
                local content_blocks = assistant_to_content_blocks(msg)
                
                local assistant_msg = {
                    role = "assistant",
                }
                
                if #content_blocks > 0 then
                    assistant_msg.content = content_blocks
                else
                    -- No content blocks, use empty string
                    assistant_msg.content = ""
                end
                
                table.insert(result, assistant_msg)
            end
        else
            -- Regular user message - pass through
            table.insert(result, msg)
        end
    end
    
    return result
end

function AnthropicClient:_add_optional_params(data)
    local temp = config.temperature()
    if temp then data.temperature = temp end
    
    local thinking_extra = config.thinking_extra_body()
    if thinking_extra then
        for k, v in pairs(thinking_extra) do
            data[k] = v
        end
    end
end

function AnthropicClient:_show_thinking()
    -- Stub for compatibility
end

function AnthropicClient:_clear_thinking()
    -- Stub for compatibility
end

return AnthropicClient
