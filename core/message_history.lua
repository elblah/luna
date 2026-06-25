-- Message history management for Luna

local log = require("utils.log")
local token_estimator = require("core.token_estimator")
local config = require("core.config")
local json = require("utils.json")
local file_utils = require("utils.file_utils")

local M = {}

M.PRUNE_TOOL_MESSAGE = "[Old tool result content cleared due to memory compaction]"
M.PRUNE_PROTECTION_THRESHOLD = 256

-- Class-style alias for 1-1 parity with Python's MessageHistory class
M.MessageHistory = M

function M.new(stats)
    local self = {
        stats = stats,
        api_client = nil,
        messages = {},
        initial_system_prompt = nil,
        is_compacting = false,
        _plugin_system = nil,
        _context_size = 0,
        _stats = stats,  -- Store for use in estimate_context
    }
    
    -- Use local ref for closures
    local this = self
    
    function self:set_plugin_system(ps)
        this._plugin_system = ps
    end
    
    function self:set_api_client(client)
        this.api_client = client
    end
    
    function self:add_system_message(content)
        local message = {role = "system", content = content}
        table.insert(this.messages, message)
        if not this.initial_system_prompt then
            this.initial_system_prompt = message
        end
        this:estimate_context()
        if this._plugin_system then
            this._plugin_system:call_hooks("after_session_initialized", this.messages)
        end
    end
    
    function self:add_user_message(content)
        local message
        if type(content) == "table" then
            message = content
        else
            message = {role = "user", content = content}
        end
        table.insert(this.messages, message)
        if this.stats then
            this.stats:increment_messages_sent()
        end
        this:estimate_context()
        if this._plugin_system then
            this._plugin_system:call_hooks("after_user_message_added", message)
        end
    end
    
    function self:get_messages()
        return this.messages
    end
    
    function self:add_assistant_message(msg)
        local assistant_message
        if type(msg) == "table" then
            -- Copy only message-relevant fields, exclude response metadata
            assistant_message = {
                role = "assistant",
            }
            for k, v in pairs(msg) do
                -- Skip response metadata fields
                if k ~= "usage" and k ~= "id" and k ~= "model" and k ~= "finish_reason" and k ~= "ok" then
                    assistant_message[k] = v
                end
            end
            -- Set empty tool_calls to nil
            if assistant_message.tool_calls and (type(assistant_message.tool_calls) ~= "table" or #assistant_message.tool_calls == 0) then
                assistant_message.tool_calls = nil
            end
        else
            assistant_message = {role = "assistant", content = msg}
        end
        table.insert(this.messages, assistant_message)
        this:estimate_context()
        if this._plugin_system then
            this._plugin_system:call_hooks("after_assistant_message_added", assistant_message)
        end
    end
    
    function self:add_tool_results(tool_results)
        local max_size = config.max_tool_result_size()
        for i, tool_result in ipairs(tool_results) do
            local content = tool_result.content or ""
            -- Truncate oversized tool results to prevent context explosion
            if #content > max_size then
                content = content:sub(1, max_size) .. "\n\n[... truncated to " .. max_size .. " chars by max_tool_result_size]"
                log.warn("[message_history] Truncated tool result (" .. #tool_result.content .. " -> " .. #content .. " chars)")
            end
            local tool_message = {
                role = "tool",
                tool_call_id = tool_result.tool_call_id or "unknown",
                content = content,
            }
            table.insert(this.messages, tool_message)
            if this._plugin_system then
                this._plugin_system:call_hooks("after_tool_results_added", tool_message)
            end
        end
        this:estimate_context()
    end
    
    function self:get_message_count()
        return #this.messages
    end
    
    function self:set_messages(messages)
        this.messages = messages or {}
        self:estimate_context()
    end
    
    function self:get_round_count()
        local count = 0
        local last_role = nil
        for _, msg in ipairs(this.messages) do
            local role = msg.role
            if role == "user" and last_role ~= "user" then
                count = count + 1
            end
            last_role = role
        end
        return count
    end
    
    function self:get_chat_messages()
        local chat = {}
        for _, msg in ipairs(this.messages) do
            if msg.role == "user" or msg.role == "assistant" then
                table.insert(chat, msg)
            end
        end
        return chat
    end

    -- Get all messages except system role (for session persistence)
    function self:get_session_messages()
        local session = {}
        for _, msg in ipairs(this.messages) do
            if msg.role ~= "system" then
                table.insert(session, msg)
            end
        end
        return session
    end
    
    function self:estimate_context()
        -- Use token_estimator with caching (like Python)
        local total = token_estimator.estimate_messages(this.messages)
        this._context_size = total
        -- Sync with stats for context bar display
        if this._stats then
            this._stats.current_prompt_size = this._context_size
        end
        return this._context_size
    end
    
    function self:should_auto_compact()
        -- Match v3: disabled by default (CONTEXT_COMPACT_PERCENTAGE=0)
        local percentage = config.context_compact_percentage()
        if percentage <= 0 then
            return false
        end
        
        local max_size = config.context_size()
        local threshold = max_size * (percentage / 100)
        
        return this._context_size > threshold
    end

    function self:clear()
        this.messages = {}
        this.initial_system_prompt = nil
        this._context_size = 0
    end

    -- Static helpers (image detection, content as string)
    local function _is_image_part(item)
        if type(item) ~= "table" then return false end
        return item.type == "image_url" or item.type == "image"
    end

    local function _get_content_as_string(content)
        if type(content) == "table" then
            for _, item in ipairs(content) do
                if _is_image_part(item) then return nil end
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

    local function _has_image_content(msg)
        local content = msg.content
        if type(content) == "table" then
            for _, item in ipairs(content) do
                if _is_image_part(item) then return true end
            end
        end
        return false
    end

    function self:_is_image_part(item) return _is_image_part(item) end
    function self:_get_content_as_string(content) return _get_content_as_string(content) end
    function self:_has_image_content(msg) return _has_image_content(msg) end

    -- Find correct insertion position for a tool result (after matching call)
    function self:_find_tool_insert_position(tool_call_id)
        for i = #this.messages, 1, -1 do
            local msg = this.messages[i]
            if msg.role == "assistant" then
                local tool_calls = msg.tool_calls
                if tool_calls and type(tool_calls) == "table" then
                    for _, call in ipairs(tool_calls) do
                        if call.id == tool_call_id then
                            return i + 1
                        end
                    end
                end
            end
        end
        return -1
    end

    -- Remove tool results with no matching parent tool call
    function self:remove_orphan_tool_results()
        local valid_call_ids = {}
        for _, msg in ipairs(this.messages) do
            if msg.role == "assistant" and msg.tool_calls and type(msg.tool_calls) == "table" then
                for _, call in ipairs(msg.tool_calls) do
                    if call.id then valid_call_ids[call.id] = true end
                end
            end
        end
        
        local orphan_count = 0
        local new_messages = {}
        local removed_ids = {}
        for _, msg in ipairs(this.messages) do
            if msg.role == "tool" then
                local tc_id = msg.tool_call_id or ""
                if not valid_call_ids[tc_id] then
                    orphan_count = orphan_count + 1
                    table.insert(removed_ids, tc_id)
                else
                    table.insert(new_messages, msg)
                end
            else
                table.insert(new_messages, msg)
            end
        end
        
        if orphan_count > 0 then
            log.debug("[!] Removed " .. orphan_count .. " orphan tool results: " .. table.concat(removed_ids, ", "))
        end
        this.messages = new_messages
        this:estimate_context()
        return orphan_count
    end

    function self:get_chat_message_count()
        return #this:get_chat_messages()
    end

    function self:get_initial_system_prompt()
        return this.initial_system_prompt
    end

    function self:increment_compaction_count()
        if this.stats then this.stats:increment_compactions() end
    end

    function self:get_compaction_count()
        if this.stats then return this.stats.compactions or 0 end
        return 0
    end

    function self:compact_memory()
        if this.is_compacting then
            log.warn("Compaction already in progress, skipping...")
            return
        end
        if not this.api_client then
            log.error("API client not available for compaction")
            return
        end
        this.is_compacting = true
        local ok, err = pcall(function()
            local CompactionService = require("core.compaction_service")
            local svc = CompactionService.new(this.api_client)
            local context_before = this:estimate_context()
            local compact_pct = config.context_compact_percentage()
            local prune_threshold = config.compact_prune_threshold()
            local max_size = config.context_size()
            local compact_at = max_size * (compact_pct / 100)
            local prune_at = max_size * (prune_threshold / 100)
            
            -- Try pruning first if we're above prune threshold but below compact threshold
            if context_before >= prune_at and context_before < compact_at then
                log.warn("[*] Pruning large tool results...")
                local pruned = this:prune_all_tool_results()
                this:estimate_context()
                if this._context_size < compact_at then
                    log.warn("[*] Pruning reduced context enough, skipping AI compaction")
                    this.is_compacting = false
                    return
                end
            end
            
            log.warn("[*] Compacting conversation (" .. context_before .. " tokens)...")
            local new_msgs = svc:compact(this.messages)
            
            -- Safety: estimate context of new messages before applying
            local old_messages = this.messages
            this.messages = new_msgs
            this:remove_orphan_tool_results()
            this:estimate_context()
            local context_after = this._context_size
            
            -- Safety: if compaction didn't reduce to at least half, abort
            local min_reduction = context_before / 2
            if context_after >= min_reduction then
                log.error("[X] Compaction ineffective: " .. context_before .. " -> " .. context_after .. " tokens (need < " .. math.floor(min_reduction) .. ").")
                -- Save recovery session before exit
                local recovery_dir = ".aicoder"
                file_utils.mkdir_p(recovery_dir)
                local ts = tostring(os.time())
                local rand = tostring(math.random(100000, 999999))
                local recovery_path = recovery_dir .. "/recovery-session-" .. ts .. "-" .. rand .. ".json"
                local f = io.open(recovery_path, "w")
                if f then
                    f:write(json.encode(old_messages))
                    f:close()
                    io.stderr:write("[message_history] Recovery session saved to: " .. recovery_path .. "\n")
                end
                io.stderr:write("[FATAL] Compaction failed to reduce context size. Exiting to prevent infinite loop.\n")
                os.exit(1)
            end
            
            this:increment_compaction_count()
            log.success("Conversation compacted: " .. context_before .. " -> " .. context_after .. " tokens")
        end)
        this.is_compacting = false
        if not ok then
            log.error("[X] Compaction failed: " .. tostring(err))
        end
    end

    function self:force_compact_rounds(n)
        if not this.api_client then
            log.error("API client not available for force compact")
            return this.messages
        end
        local CompactionService = require("core.compaction_service")
        local svc = CompactionService.new(this.api_client)
        local new_msgs = svc:force_compact_rounds(this.messages, n)
        this.messages = new_msgs
        this:remove_orphan_tool_results()
        this:estimate_context()
        this:increment_compaction_count()
        return new_msgs
    end

    function self:force_compact_messages(n)
        if not this.api_client then
            log.error("API client not available for force compact")
            return this.messages
        end
        local CompactionService = require("core.compaction_service")
        local svc = CompactionService.new(this.api_client)
        local new_msgs = svc:force_compact_messages(this.messages, n)
        this.messages = new_msgs
        this:remove_orphan_tool_results()
        this:estimate_context()
        this:increment_compaction_count()
        return new_msgs
    end

    function self:get_tool_result_messages()
        local result = {}
        for _, msg in ipairs(this.messages) do
            if msg.role == "tool" then table.insert(result, msg) end
        end
        return result
    end

    function self:get_tool_call_stats()
        local tool_messages = this:get_tool_result_messages()
        local count = #tool_messages
        local total_content = ""
        for _, msg in ipairs(tool_messages) do
            if msg.content then total_content = total_content .. tostring(msg.content) end
        end
        return {
            count = count,
            tokens = math.floor(#total_content / 4),
            bytes = #total_content,
        }
    end

    function self:insert_user_message_at_appropriate_position(content)
        local last_tool_index = -1
        local last_assistant_index = -1
        local last_user_index = -1
        for i = #this.messages, 1, -1 do
            local msg = this.messages[i]
            local role = msg.role
            if role == "tool" and last_tool_index == -1 then
                last_tool_index = i
            elseif role == "assistant" then
                local tc = msg.tool_calls
                if (not tc or #tc == 0) and last_assistant_index == -1 then
                    last_assistant_index = i
                end
            elseif role == "user" and last_user_index == -1 then
                last_user_index = i
            end
        end
        local insertion_index = #this.messages + 1
        if last_tool_index >= 0 then
            insertion_index = last_tool_index + 1
        elseif last_assistant_index >= 0 then
            insertion_index = last_assistant_index + 1
        elseif last_user_index >= 0 then
            insertion_index = last_user_index + 1
        end
        table.insert(this.messages, insertion_index, {role = "user", content = content})
        this:estimate_context()
    end

    function self:replace_messages(new_messages)
        this.messages = new_messages or {}
        this:estimate_context()
    end

    function self:prune_tool_results(indices)
        local tool_messages = this:get_tool_result_messages()
        local pruned_count = 0
        for _, index in ipairs(indices) do
            if index >= 0 and index < #tool_messages then
                local tool_message = tool_messages[index]
                for i, msg in ipairs(this.messages) do
                    if msg == tool_message then
                        local current_content = msg.content or ""
                        local current_size = #current_content
                        if current_size > math.max(#M.PRUNE_TOOL_MESSAGE, M.PRUNE_PROTECTION_THRESHOLD) then
                            msg.content = M.PRUNE_TOOL_MESSAGE
                            pruned_count = pruned_count + 1
                        end
                        break
                    end
                end
            end
        end
        this:estimate_context()
        return pruned_count
    end

    function self:prune_all_tool_results()
        local tool_messages = this:get_tool_result_messages()
        local indices = {}
        for i = 1, #tool_messages do table.insert(indices, i) end
        return this:prune_tool_results(indices)
    end

    function self:prune_oldest_tool_results(n)
        local tool_messages = this:get_tool_result_messages()
        local indices = {}
        for i = 1, math.min(n, #tool_messages) do table.insert(indices, i) end
        return this:prune_tool_results(indices)
    end

    function self:prune_keep_newest_tool_results(keep_count)
        local tool_messages = this:get_tool_result_messages()
        if keep_count >= #tool_messages then return 0 end
        local prune_count = #tool_messages - keep_count
        local indices = {}
        for i = 1, prune_count do table.insert(indices, i) end
        return this:prune_tool_results(indices)
    end

    function self:prune_tool_results_by_percentage(target_percentage)
        target_percentage = target_percentage or 50
        local tool_messages = this:get_tool_result_messages()
        if #tool_messages == 0 then
            return {prunedCount = 0, totalSize = 0, actualPercentage = 0}
        end
        local sorted = {}
        for i, msg in ipairs(tool_messages) do
            table.insert(sorted, {index = i, msg = msg, size = #(msg.content or "")})
        end
        table.sort(sorted, function(a, b) return a.size > b.size end)
        local total_size = 0
        for _, s in ipairs(sorted) do total_size = total_size + s.size end
        local target_size = math.floor((total_size * (100 - target_percentage)) / 100)
        local current_size = total_size
        local pruned_indices = {}
        for _, s in ipairs(sorted) do
            if current_size <= target_size then break end
            if s.size > math.max(#M.PRUNE_TOOL_MESSAGE, M.PRUNE_PROTECTION_THRESHOLD) then
                table.insert(pruned_indices, s.index)
                current_size = current_size - s.size + #M.PRUNE_TOOL_MESSAGE
            end
        end
        local pruned = this:prune_tool_results(pruned_indices)
        return {prunedCount = pruned, totalSize = total_size, actualPercentage = 0}
    end

    function self:prune_old_summaries()
        local summary_indices = {}
        for i, msg in ipairs(this.messages) do
            local content = _get_content_as_string(msg.content)
            if content and content:match("^%[SUMMARY%]") then
                table.insert(summary_indices, i)
            end
        end
        if #summary_indices <= 1 then return 0 end
        local keep_index = summary_indices[#summary_indices]
        local prune_indices = {}
        for i = 1, #summary_indices - 1 do table.insert(prune_indices, summary_indices[i]) end
        local pruned_count = 0
        table.sort(prune_indices, function(a, b) return a > b end)
        for _, idx in ipairs(prune_indices) do
            table.remove(this.messages, idx)
            pruned_count = pruned_count + 1
        end
        this:estimate_context()
        return pruned_count
    end

    function self:keep_last_message()
        if #this.messages <= 1 then return 0 end
        local last_message = this.messages[#this.messages]
        local content = _get_content_as_string(last_message.content)
        local needs_placeholder = last_message.role ~= "user" or (content and content:match("^%[SUMMARY%]"))
        if needs_placeholder then
            this.messages = {{role = "user", content = "..."}, last_message}
        else
            this.messages = {last_message}
        end
        this:estimate_context()
        return 1
    end

    return self
end

return M
