-- Context Bar for Luna
-- 1-1 port from Python context_bar.py

local config = require("core.config")

local ContextBar = {}
ContextBar.__index = ContextBar

function ContextBar.new(plugin_system)
    local self = setmetatable({}, ContextBar)
    self.plugin_system = plugin_system
    return self
end

function ContextBar:format_context_bar(stats, message_history)
    -- Context size is automatically updated when messages are added
    local current_tokens = stats.current_prompt_size or 0
    local max_tokens = config.context_size()
    
    -- Guard against invalid values
    local percentage = 0
    if max_tokens > 0 and current_tokens and max_tokens then
        percentage = (current_tokens / max_tokens) * 100
        if percentage > 999 then
            percentage = 999
        end
    end
    
    local percentage_str = string.format("%.0f", percentage)
    
    -- Format progress bar
    local progress_bar = self:create_progress_bar(percentage)
    
    -- Format current tokens (in k if large)
    local current_tokens_str
    if current_tokens > 1000 then
        current_tokens_str = string.format("%.1fk", current_tokens / 1000)
    else
        current_tokens_str = tostring(current_tokens)
    end
    
    local max_tokens_str
    if max_tokens > 1000 then
        max_tokens_str = string.format("%.1fk", max_tokens / 1000)
    else
        max_tokens_str = tostring(max_tokens)
    end
    
    -- Get model name
    local model = config.model() or "unknown"
    local model_short = model:match("([^/]+)$") or model
    
    -- Add YOLO indicator if enabled
    local yolo_suffix = ""
    if config.yolo_mode() then
        yolo_suffix = config.colors.yellow .. config.colors.bold .. " YOLO" .. config.colors.reset
    end
    
    -- Build the base context bar
    local context_bar = string.format("Context: %s %s%% (%s/%s @%s%s)", 
        progress_bar, percentage_str, current_tokens_str, max_tokens_str, model_short, yolo_suffix)
    
    -- Add time at the end
    local time_str = self:get_current_hour()
    
    -- Add last API time if available
    local last_api = stats.last_api_time or 0
    local api_time_str = nil
    if last_api and last_api > 0 then
        if last_api >= 60 then
            local mins = math.floor(last_api / 60)
            local secs = math.floor(last_api % 60)
            api_time_str = string.format("%dm%ds", mins, secs)
        else
            api_time_str = string.format("%.0fs", last_api)
        end
    end
    
    -- Build core suffix
    local core_suffix = ""
    if time_str and api_time_str then
        core_suffix = " - " .. time_str .. " - " .. api_time_str
    elseif time_str then
        core_suffix = " - " .. time_str
    elseif api_time_str then
        core_suffix = " - " .. api_time_str
    end
    
    -- Call plugins for context bar extensions (e.g., git status) - extend from core end
    local extensions = ""
    if self.plugin_system then
        extensions = self.plugin_system:call_hooks_with_return("on_context_bar", "")
        if extensions and extensions ~= "" and extensions ~= nil then
            extensions = config.colors.dim .. " - " .. config.colors.reset .. extensions
        end
    end
    
    return context_bar .. core_suffix .. extensions
end

function ContextBar:get_current_hour()
    local now = os.date("*t")
    return string.format("%02d:%02d:%02d", now.hour, now.min, now.sec)
end

function ContextBar:create_progress_bar(percentage)
    local bar_width = 10
    
    -- Guard against invalid percentage values
    local safe_percentage = math.max(0, math.min(100, percentage or 0))
    
    local filled_chars = math.floor((safe_percentage / 100) * bar_width)
    local empty_chars = math.max(0, bar_width - filled_chars)
    
    -- Choose color based on percentage
    local color
    if safe_percentage <= 30 then
        color = "\x1b[32m"  -- green
    elseif safe_percentage <= 80 then
        color = "\x1b[33m"  -- yellow
    else
        color = "\x1b[31m"  -- red
    end
    
    local reset = "\x1b[0m"
    local dim = "\x1b[2m"
    
    -- Use unicode block characters for progress bar
    local filled_bar = string.rep("█", filled_chars)
    local empty_bar = string.rep("░", empty_chars)
    
    return color .. filled_bar .. dim .. empty_bar .. reset
end

function ContextBar:print_context_bar(stats, message_history)
    local context_bar = self:format_context_bar(stats, message_history)
    print(context_bar)
end

function ContextBar:print_context_bar_for_user(stats, message_history)
    local context_bar = self:format_context_bar(stats, message_history)
    print("\n" .. context_bar)
end

return ContextBar