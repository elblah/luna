-- Session manager - simplified non-streaming version

local config = require("core.config")
local log = require("utils.log")
local MarkdownColorizer = require("core.markdown_colorizer")

local show_reasoning = os.getenv("AICODER_SHOW_REASONING") ~= "0"

local SessionManager = {}
SessionManager.__index = SessionManager

function SessionManager.new(app)
    local self = setmetatable({}, SessionManager)
    self.app = app
    self.message_history = app.message_history
    self.api_client = app.api_client
    self.tool_executor = app.tool_executor
    self.context_bar = app.context_bar
    self.stats = app.stats
    self.compaction_service = app.compaction_service
    self.plugin_system = app.plugin_system
    self.is_processing = false
    self.colorizer = MarkdownColorizer.new()
    return self
end

-- Append assistant response to SESSION_OUTPUT_FILE (JSONL)
function SessionManager:_append_to_output_file(content, tool_calls, response)
    local output_file = config.session_output_file()
    if output_file == "" then return end
    
    local json = require("utils.json")
    local entry = {
        role = "assistant",
        content = content,
        timestamp = os.time(),
    }
    if tool_calls and #tool_calls > 0 then
        entry.tool_calls = tool_calls
    end
    -- Include reasoning if present
    local reasoning = response.thinking or response.reasoning_content or response.reasoning
    if reasoning and type(reasoning) == "string" and reasoning ~= "" then
        entry.reasoning = reasoning
    end
    
    local f, err = io.open(output_file, "a")
    if f then
        f:write(json.encode(entry) .. "\n")
        f:close()
    end
end

function SessionManager:process_with_ai()
    if config.debug() then
        log.debug("*** process_with_ai called")
    end
    
    -- Reset cancellation flag for new AI operation
    _G.processing_cancelled = false
    
    self.is_processing = true
    
    local ok, err = pcall(function()
        -- Show context bar before AI response
        print()
        if self.context_bar then
            self.context_bar:print_context_bar(self.stats, self.message_history)
        end
        
        -- Call plugin hook before AI processing starts
        if self.plugin_system then
            self.plugin_system:call_hooks("before_ai_processing")
        end
        
        log.printc("AI: ", {color = "cyan", bold = true})
        
        -- Check if interrupted
        if not self.is_processing or _G.processing_cancelled then
            print("\n[AI response interrupted before starting]")
            return
        end
        
        -- Show thinking indicator
        io.write(config.colors.dim .. "Thinking..." .. config.colors.reset)
        io.flush()
        
        local messages = self.message_history:get_messages()
        
        -- Call API with retry for temporary errors
        local response = self:_call_api_with_retry({
            messages = messages,
            send_tools = true
        })
        
        -- Clear thinking indicator (success path)
        io.write("\r\27[K")
        io.flush()
        
        -- Handle API response
        self:_handle_api_response(response)
    end)
    
    if not ok then
        -- Check if cancelled via Ctrl+C
        if _G.processing_cancelled then
            -- Clear thinking/error line, return to prompt silently
            io.write("\r\27[K")
            io.flush()
            self.is_processing = false
            return
        end
        self:_handle_processing_error(err)
    end
    
    self.is_processing = false
end

function SessionManager:_handle_api_response(response)
    -- Non-streaming: response is one complete block
    -- Just pass it through with role="assistant" added by message_history
    if response.ok == false then
        error(string.format("API Error: HTTP %d - %s", response.status, response.error))
    end
    
    local content = response.content
    local has_content = type(content) == "string" and content:gsub("%s+", "") ~= ""
    
    if not response.tool_calls or type(response.tool_calls) ~= "table" or #response.tool_calls == 0 then
        -- No tool calls - text response or empty
        if has_content then
            self.message_history:add_assistant_message(response)
            self:_append_to_output_file(content, nil, response)
            -- Print reasoning if present
            local reasoning = response.thinking or response.reasoning_content or response.reasoning
            if reasoning and type(reasoning) == "string" and reasoning ~= "" and show_reasoning then
                print()
                print(config.colors.dim .. "Reasoning: " .. reasoning .. config.colors.reset)
            end
            print()
            self.colorizer:reset_state()
            print(self.colorizer:print_with_colorization(content))
        else
            -- Empty response - this triggers empty_retry via after_ai_processing hook
            self.message_history:add_assistant_message({content = ""})
            self:_append_to_output_file("", nil, {})
        end
        -- Call plugin hooks after AI processing (no tool calls case)
        if self.plugin_system then
            local hook_results = self.plugin_system:call_hooks("after_ai_processing", false)
            if hook_results then
                for _, result in ipairs(hook_results) do
                    if result and type(result) == "string" then
                        self.app:set_next_prompt(result)
                    end
                end
            end
        end
    else
        -- Has tool calls
        local valid_tool_calls = self:_validate_tool_calls(response.tool_calls)
        if not valid_tool_calls or #valid_tool_calls == 0 then
            log.error("No valid tool calls to execute")
            self.message_history:add_user_message(
                "ERROR: The tool calls you sent had invalid JSON format and could not be processed. Please try again with properly formatted JSON."
            )
            -- Continue processing
            self:_handle_post_tool_processing(false, "validation_error")
            return
        end
        
        -- Add assistant message with tool calls
        local tool_calls_for_message = {}
        for i, call in ipairs(valid_tool_calls) do
            table.insert(tool_calls_for_message, {
                id = call.id,
                type = call.type or "function",
                ["function"] = {
                    name = call["function"] and call["function"].name,
                    arguments = call["function"] and call["function"].arguments,
                },
                index = i - 1,
            })
        end
        
        -- Preserve original response (including reasoning with whatever field name)
        local assistant_message = {}
        for k, v in pairs(response) do
            assistant_message[k] = v
        end
        assistant_message.tool_calls = tool_calls_for_message
        if assistant_message.content == "" or not assistant_message.content then
            assistant_message.content = "I'll help you with that."
        end
        
        self.message_history:add_assistant_message(assistant_message)
        self:_append_to_output_file(assistant_message.content, tool_calls_for_message, response)
        
        -- Print reasoning and content if present
        local reasoning = response.thinking or response.reasoning_content or response.reasoning
        local content = response.content
        local has_content = type(content) == "string" and content:gsub("%s+", "") ~= ""
        
        if reasoning and reasoning ~= "" and show_reasoning then
            print()
            print(config.colors.dim .. "Reasoning: " .. reasoning .. config.colors.reset)
            if has_content then
                print()
            end
        end
        if has_content then
            self.colorizer:reset_state()
            print(self.colorizer:print_with_colorization(content))
        end
        
        -- Execute tools
        self.tool_executor:execute_tool_calls(valid_tool_calls)
        
        self:_handle_post_tool_processing(true, "success")
    end
end

-- Temporary error codes that should trigger retry
local TEMP_ERROR_CODES = {
    [0] = true,   -- Network/TLS/connection errors
    [401] = true,  -- Unauthorized (transient auth failures)
    [429] = true,  -- Too Many Requests
    [500] = true,  -- Internal Server Error
    [502] = true,  -- Bad Gateway
    [503] = true,  -- Service Unavailable
    [504] = true,  -- Gateway Timeout
}

-- Sleep helper: returns false if interrupted (Ctrl+C killed the child)
local function sleep_secs(n)
    local ret = os.execute("sleep " .. n)
    if ret ~= 0 then
        -- os.execute blocks SIGINT in parent, but child was killed by signal
        _G.processing_cancelled = true
        return false
    end
    return true
end

function SessionManager:_call_api_with_retry(request)
    local max_attempts = 10
    local attempt = 1
    
    while attempt <= max_attempts do
        -- Check if cancelled (Ctrl+C)
        if _G.processing_cancelled then
            error("Request cancelled by user")
        end
        
        local ok, response = pcall(function()
            return self.api_client:send_request(request)
        end)
        
        if ok and response and response.ok then
            return response
        elseif ok and response and not response.ok then
            -- API returned error
            local status = response.status
            if status and TEMP_ERROR_CODES[status] then
                local delay = math.min(2 ^ attempt, 30)  -- Exponential backoff, max 30s
                log.warn(string.format("Attempt %d/%d failed: HTTP %d - %s", attempt, max_attempts, status, response.error))
                log.warn(string.format("Retrying in %ds...", delay))
                -- Sleep with Ctrl+C detection
                if not sleep_secs(delay) then
                    error("Request cancelled by user")
                end
                attempt = attempt + 1
            else
                -- Permanent error
                error(string.format("API Error: HTTP %d - %s", status, response.error))
            end
        else
            -- pcall failed (unexpected error)
            error(tostring(response))
        end
    end
    
    error(string.format("All %d attempts failed", max_attempts))
end

function SessionManager:_handle_post_tool_processing(has_tool_calls, status)
    -- Check if user requested guidance mode (stop after current tool)
    if self.tool_executor:is_guidance_mode() then
        log.success("[*] Guidance mode: Your turn - tell the AI how to proceed")
        self.tool_executor:clear_guidance_mode()
        return
    end

    -- Call plugin hooks after AI processing (BEFORE recurse, like v3)
    if self.plugin_system then
        local hook_results = self.plugin_system:call_hooks("after_ai_processing", has_tool_calls)
        if hook_results then
            for _, result in ipairs(hook_results) do
                if result and type(result) == "string" then
                    self.app:set_next_prompt(result)
                end
            end
        end
    end

    -- Trigger compaction if needed (after tool execution)
    if has_tool_calls and self.is_processing and self.message_history:should_auto_compact() then
        self:_perform_auto_compaction()
    end

    -- Normal processing continuation
    if self.is_processing then
        if has_tool_calls then
            self:process_with_ai()
        elseif status == "validation_error" then
            self:process_with_ai()
        end
        -- status == "empty_response": done (plugin hook set next_prompt if needed)
    end
end

function SessionManager:_handle_processing_error(error)
    -- Clear thinking indicator if still showing
    io.write("\r\27[K")
    io.flush()
    log.error("Processing error: " .. tostring(error))
end

function SessionManager:_validate_tool_calls(tool_calls)
    if type(tool_calls) ~= "table" then
        return {}
    end
    local valid_tool_calls = {}
    local json = require("utils.json")
    
    for _, tool_call in pairs(tool_calls) do
        -- Basic structure validation
        local func = tool_call["function"] or {}
        if not (func.name and tool_call.id) then
            goto continue
        end
        
        local arguments_raw = func.arguments or ""
        
        -- Validate JSON format - reject if malformed
        if type(arguments_raw) == "string" then
            local ok, _ = pcall(function() json.decode(arguments_raw) end)
            if not ok then
                if config.debug() then
                    log.warn("[!] Malformed JSON in tool call '" .. (func.name or "unknown") .. "': " .. arguments_raw)
                end
                goto continue  -- Skip this tool call entirely
            end
        end
        
        table.insert(valid_tool_calls, tool_call)
        
        ::continue::
    end
    
    return valid_tool_calls
end

-- v3-style: delegate to message_history:compact_memory()
-- Plugins can intercept via before_auto_compaction hook.
-- Hook returns true to skip AI compaction (e.g., if pruning was effective).
function SessionManager:_perform_auto_compaction()
    -- Call before_auto_compaction hook - skip if plugin handles it
    if self.plugin_system then
        local skip_compaction = self.plugin_system:call_hooks_with_return("before_auto_compaction")
        if skip_compaction == true then
            return
        end
    end

    self.message_history:compact_memory()
end

function SessionManager:_ensure_tool_calls_have_responses()
    local messages = self.message_history.messages
    local i = 1
    
    while i <= #messages do
        local msg = messages[i]
        
        if msg.role == "assistant" and msg.tool_calls and type(msg.tool_calls) == "table" and #msg.tool_calls > 0 then
            -- Check if next message is a tool response
            local next_msg = messages[i + 1]
            if not next_msg or next_msg.role ~= "tool" then
                -- Missing tool response - insert placeholder
                log.warn("[!] Tool call without response, inserting placeholder")
                table.insert(messages, i + 1, {
                    role = "tool",
                    tool_call_id = msg.tool_calls[1] and msg.tool_calls[1].id or "unknown",
                    content = "[Placeholder - tool execution info not captured]"
                })
            end
        end
        
        i = i + 1
    end
end

return SessionManager
