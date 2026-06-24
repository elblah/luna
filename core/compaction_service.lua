-- Compaction Service for Luna
-- 1-1 port from Python compaction_service.py
-- Centralized compaction: takes messages, returns compacted messages.

-- Lua/LuaJIT compatibility: table.unpack doesn't exist in LuaJIT
local unpack = unpack or table.unpack

local config = require("core.config")
local log = require("utils.log")

local M = {}

-- Class-style aliases for 1-1 parity with Python's classes
M.CompactionService = M
M.MessageGroup = M
M.MessageGroup.classify_messages = M.classify_messages or function() end

-- Image part detection
local function is_image_part(item)
    if type(item) ~= "table" then return false end
    return item.type == "image_url" or item.type == "image"
end

-- Safely get content as string. Returns nil if image-only.
local function get_content_as_string(content)
    if type(content) == "table" then
        for _, item in ipairs(content) do
            if is_image_part(item) then
                return nil
            end
        end
        for _, item in ipairs(content) do
            if type(item) == "table" and item.type == "text" then
                return item.text or ""
            end
        end
        return ""
    end
    if content == nil then return "" end
    return tostring(content)
end

local function has_image_content(msg)
    local content = msg.content
    if type(content) == "table" then
        for _, item in ipairs(content) do
            if is_image_part(item) then return true end
        end
    end
    return false
end

-- Validate summary quality
local function validate_summary(summary)
    return summary and type(summary) == "string" and #summary >= 100
end

-- Create summary message (user role to avoid model issues)
local function create_summary_message(summary)
    return {
        role = "user",
        content = "[SUMMARY] " .. summary,
    }
end

-- Format messages for AI summarization
local function format_messages_for_summary(self, messages)
    local total = #messages
    local result = {}

    for i, msg in ipairs(messages) do
        local role = msg.role
        local content = get_content_as_string(msg.content)
        if not content or content == "" then goto continue end

        local current_index = i
        local position_percent = (current_index / total) * 100
        local priority
        if position_percent >= 80 then
            priority = "VERY RECENT (Last 20%)"
        elseif position_percent >= 60 then
            priority = "RECENT (Last 40%)"
        elseif position_percent >= 30 then
            priority = "MIDDLE"
        else
            priority = "OLD (First 30%)"
        end

        local prefix = string.format("[%03d/%d] %s ", current_index, total, priority)

        if role == "assistant" then
            local tool_calls = msg.tool_calls
            if tool_calls and type(tool_calls) == "table" and #tool_calls > 0 then
                local tool_lines = {}
                for _, call in ipairs(tool_calls) do
                    local fn = call["function"] or {}
                    local name = fn.name or "unknown"
                    local args = fn.arguments or "{}"
                    table.insert(tool_lines, "Tool Call: " .. name .. "(" .. args .. ")")
                end
                table.insert(result, prefix .. " Assistant: " .. content .. "\n" .. table.concat(tool_lines, "\n"))
            else
                table.insert(result, prefix .. " Assistant: " .. content)
            end
        elseif role == "tool" then
            local tool_call_id = msg.tool_call_id or "unknown"
            local tool_content = content
            if #tool_content > 500 then
                tool_content = tool_content:sub(1, 500) .. "... (truncated for summarization)"
            end
            table.insert(result, prefix .. " Tool Result (ID: " .. tool_call_id .. "): " .. tool_content)
        elseif role == "user" then
            table.insert(result, prefix .. " User: " .. content)
        else
            local rname = role and role:sub(1, 1):upper() .. role:sub(2) or "Unknown"
            table.insert(result, prefix .. " " .. rname .. ": " .. content)
        end
        table.insert(result, "---")
        ::continue::
    end

    return table.concat(result, "\n")
end

-- Get AI summary
local function get_ai_summary(self, groups)
    local messages = {}
    for _, g in ipairs(groups) do
        for _, m in ipairs(g.messages) do
            table.insert(messages, m)
        end
    end

    local to_summarize = {}
    for _, msg in ipairs(messages) do
        if has_image_content(msg) then goto continue end
        local content = get_content_as_string(msg.content)
        if content and not content:match("^%[SUMMARY%]") then
            table.insert(to_summarize, msg)
        end
        ::continue::
    end

    if #to_summarize == 0 then
        return "No previous content"
    end

    local prompt = string.format([[Generate a self-contained session summary. This will be the ONLY context retained.

**CRITICAL: Output must be at minimum 100 characters.**
If the conversation contains only routine tool calls with no significant decisions or changes,
output: "Routine session - %d messages processed. No significant decisions, file modifications, or user decisions occurred. All interactions were routine tool invocations."
Otherwise, include all important details.

Conversation:
%s

---

Include:
- Task and progress made
- Key decisions with rationale
- Current state: files modified/created (with paths and line numbers)
- Failed approaches to avoid repeating
- Session flow: brief narrative of exploration, iterations, user corrections (3-5 sentences)
- Next steps

Guidelines:
- Be specific: file paths, function names, line numbers
- Be assertive: no questions at the end
- No meta-commentary: the summary IS the output
- 800-1500 tokens depending on complexity]], #to_summarize, format_messages_for_summary(self, to_summarize))

    local system_prompt = [[You are a helpful AI assistant tasked with summarizing conversations for context preservation.

The summary you generate will be the ONLY context retained. It must be self-contained and actionable.

Prioritize:
- Specific file paths and line numbers over general descriptions
- Rationale behind decisions, not just outcomes
- Failed approaches to prevent repeated mistakes
- Narrative flow showing how the session progressed]]

    if not self.api_client then
        log.warn("[!] No API client available for summarization")
        return "Previous conversation condensed: " .. #to_summarize .. " messages"
    end

    local summary_messages = {
        {role = "system", content = system_prompt},
        {role = "user", content = prompt},
    }

    local full_response = ""
    local ok, err = pcall(function()
        local response = self.api_client:send_request({messages = summary_messages, send_tools = false})
        
        -- Check for API error
        if not response then
            error("Empty response from API")
        end
        
        if response.ok == false or response.error then
            error("API Error: " .. (response.error or "unknown"))
        end
        
        -- send_request returns {ok=true, content=...} - extract content directly
        full_response = response.content or ""
    end)

    if not ok then
        error("AI summarization failed: " .. tostring(err))
    end

    if config.debug() then
        log.warn("[!] Compaction: got summary response (" .. #full_response .. " chars)")
    end

    if not validate_summary(full_response) then
        log.warn("[!] Generated summary too short (" .. #full_response .. " chars) - skipping compaction")
        return nil
    end

    return full_response ~= "" and full_response or "Conversation summarized"
end

-- Identify conversation rounds
local function identify_rounds(self, messages)
    local rounds = {}
    local current = {}

    for _, msg in ipairs(messages) do
        if has_image_content(msg) then goto continue end
        local content = get_content_as_string(msg.content)
        if msg.role == "system" or (content and content:match("^%[SUMMARY%]")) then
            goto continue
        end
        table.insert(current, msg)
        if msg.role == "user" and #current > 1 then
            local first_content = get_content_as_string(current[1].content)
            table.insert(rounds, {
                messages = {unpack(current, 1, #current - 1)},
                is_summary = first_content and first_content:match("^%[SUMMARY%]") ~= nil,
                is_user_turn = current[1].role == "user",
            })
            current = {msg}
        end
        ::continue::
    end

    if #current > 0 then
        local first_content = get_content_as_string(current[1].content)
        table.insert(rounds, {
            messages = current,
            is_summary = first_content and first_content:match("^%[SUMMARY%]") ~= nil,
            is_user_turn = current[1].role == "user",
        })
    end

    return rounds
end

-- Group messages into atomic units
local function group_messages(self, messages)
    local groups = {}
    local current = {}

    for _, msg in ipairs(messages) do
        if has_image_content(msg) then goto continue end
        table.insert(current, msg)
        if msg.role == "tool" or (msg.role == "user" and #current > 1) then
            local first_content = get_content_as_string(current[1].content)
            table.insert(groups, {
                messages = {unpack(current)},
                is_summary = first_content and first_content:match("^%[SUMMARY%]") ~= nil,
                is_user_turn = current[1].role == "user",
            })
            if msg.role == "user" then
                current = {msg}
            else
                current = {}
            end
        end
        ::continue::
    end

    if #current > 0 then
        local first_content = get_content_as_string(current[1].content)
        table.insert(groups, {
            messages = current,
            is_summary = first_content and first_content:match("^%[SUMMARY%]") ~= nil,
            is_user_turn = current[1].role == "user",
        })
    end

    return groups
end

-- Replace a range of messages with a summary
local function replace_messages_with_summary(self, messages, to_replace, summary_msg)
    if #to_replace == 0 then return messages end

    local first_index
    for i, msg in ipairs(messages) do
        if msg == to_replace[1] then
            first_index = i
            break
        end
    end
    if not first_index then return messages end

    local last_index
    for i = #messages, 1, -1 do
        if messages[i] == to_replace[#to_replace] then
            last_index = i
            break
        end
    end
    if not last_index then return messages end

    local result = {}
    for i = 1, first_index - 1 do
        table.insert(result, messages[i])
    end
    table.insert(result, summary_msg)
    for i = last_index + 1, #messages do
        table.insert(result, messages[i])
    end
    return result
end

function M.new(api_client)
    local self = {
        api_client = api_client,
    }

    function self:_is_image_part(item) return is_image_part(item) end
    function self:_get_content_as_string(content) return get_content_as_string(content) end
    function self:_has_image_content(msg) return has_image_content(msg) end
    function self:_validate_summary(summary) return validate_summary(summary) end
    function self:_create_summary_message(summary) return create_summary_message(summary) end
    function self:_format_messages_for_summary(messages) return format_messages_for_summary(self, messages) end
    function self:_get_ai_summary(groups) return get_ai_summary(self, groups) end
    function self:_identify_rounds(messages) return identify_rounds(self, messages) end
    function self:group_messages(messages) return group_messages(self, messages) end
    function self:_replace_messages_with_summary(messages, to_replace, summary_msg)
        return replace_messages_with_summary(self, messages, to_replace, summary_msg)
    end

    function self:compact(messages)
        if #messages <= 3 then return messages end

        local system_message = messages[1]
        local other_summaries = {}
        local messages_to_compact = {}

        for i, msg in ipairs(messages) do
            if has_image_content(msg) then goto continue end
            local content = get_content_as_string(msg.content)
            if content and content:match("^%[SUMMARY%]") then
                table.insert(other_summaries, msg)
            elseif i == 1 and msg.role == "system" then
                -- skip system
            else
                table.insert(messages_to_compact, msg)
            end
            ::continue::
        end

        local groups = group_messages(self, messages_to_compact)
        local protect = config.compact_protect_rounds()
        
        local recent_groups = {}
        if #groups > protect then
            for i = #groups - protect + 1, #groups do
                table.insert(recent_groups, groups[i])
            end
        end
        
        local old_groups = {}
        if #recent_groups < #groups then
            for i = 1, #groups - #recent_groups do
                table.insert(old_groups, groups[i])
            end
        end

        if #old_groups == 0 then return messages end

        local ok, summary = pcall(get_ai_summary, self, old_groups)
        if not ok then
            log.error("[X] Compaction failed: " .. tostring(summary))
            error(summary)
        end
        if summary == nil then return messages end

        local summary_message = create_summary_message(summary)

        local recent_messages = {}
        for _, g in ipairs(recent_groups) do
            for _, m in ipairs(g.messages) do
                table.insert(recent_messages, m)
            end
        end

        local new_messages = {system_message}
        for _, s in ipairs(other_summaries) do table.insert(new_messages, s) end
        table.insert(new_messages, summary_message)
        for _, m in ipairs(recent_messages) do table.insert(new_messages, m) end

        return new_messages
    end

    function self:force_compact_rounds(messages, n)
        local rounds = identify_rounds(self, messages)
        if #rounds == 0 then return messages end

        local rounds_to_compact
        if n < 0 then
            local keep = math.abs(n)
            rounds_to_compact = {}
            local max_to_compact = math.max(0, #rounds - keep)
            for i = 1, max_to_compact do table.insert(rounds_to_compact, rounds[i]) end
        else
            rounds_to_compact = {}
            local max_n = math.min(n, #rounds)
            for i = 1, max_n do table.insert(rounds_to_compact, rounds[i]) end
        end

        if #rounds_to_compact == 0 then return messages end

        local to_compact = {}
        for _, r in ipairs(rounds_to_compact) do
            for _, m in ipairs(r.messages) do table.insert(to_compact, m) end
        end

        local filtered = {}
        for _, msg in ipairs(to_compact) do
            if has_image_content(msg) then goto continue end
            local content = get_content_as_string(msg.content)
            if content and not content:match("^%[SUMMARY%]") then
                table.insert(filtered, msg)
            end
            ::continue::
        end

        if #filtered == 0 then return messages end

        local groups = {}
        for _, msg in ipairs(filtered) do
            table.insert(groups, {messages = {msg}, is_summary = false, is_user_turn = false})
        end

        local ok, summary = pcall(get_ai_summary, self, groups)
        if not ok then
            log.error("[X] Force compact rounds failed: " .. tostring(summary))
            error(summary)
        end
        if summary == nil then return messages end

        local summary_message = create_summary_message(summary)
        return replace_messages_with_summary(self, messages, filtered, summary_message)
    end

    function self:force_compact_messages(messages, n)
        local eligible = {}
        for _, msg in ipairs(messages) do
            if msg.role == "system" then goto continue end
            if has_image_content(msg) then goto continue end
            local content = get_content_as_string(msg.content)
            if content and not content:match("^%[SUMMARY%]") then
                table.insert(eligible, msg)
            end
            ::continue::
        end

        if #eligible == 0 then return messages end

        local to_compact
        if n < 0 then
            local keep = math.abs(n)
            to_compact = {}
            local max_n = math.max(0, #eligible - keep)
            for i = 1, max_n do table.insert(to_compact, eligible[i]) end
        else
            to_compact = {}
            local max_n = math.min(n, #eligible)
            for i = 1, max_n do table.insert(to_compact, eligible[i]) end
        end

        if #to_compact == 0 then return messages end

        local groups = {}
        for _, msg in ipairs(to_compact) do
            table.insert(groups, {messages = {msg}, is_summary = false, is_user_turn = false})
        end

        local ok, summary = pcall(get_ai_summary, self, groups)
        if not ok then
            log.error("[X] Force compact messages failed: " .. tostring(summary))
            error(summary)
        end
        if summary == nil then return messages end

        local summary_message = create_summary_message(summary)
        return replace_messages_with_summary(self, messages, to_compact, summary_message)
    end

    return self
end

return M
