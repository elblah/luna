-- Context size command - view or change context size
-- Ported from Python commands/context_size.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local config = require("core.config")
local log = require("utils.log")

local ContextSizeCommand = setmetatable({}, {__index = BaseCommand})
ContextSizeCommand.__index = ContextSizeCommand

function ContextSizeCommand.new(context)
    local self = setmetatable({}, ContextSizeCommand)
    self.context = context
    return self
end

function ContextSizeCommand:get_name()
    return "context-size"
end

function ContextSizeCommand:get_description()
    return "View or change context size"
end

function ContextSizeCommand:get_aliases()
    return {"cs"}
end

local function parse_size(value)
    value = value:lower()
    
    if value == "default" then
        return config.context_size()  -- Return current for "default"
    end
    
    if value:match("^%d+k$") then
        local num = tonumber(value:sub(1, -2))
        if not num then return nil end
        return math.floor(num * 1000)
    end
    
    if value:match("^%d+%.?%d*m$") then
        local num = tonumber(value:sub(1, -2))
        if not num then return nil end
        return math.floor(num * 1000000)
    end
    
    return tonumber(value)
end

local function format_size(size)
    if size >= 1000000 then
        return string.format("%.1fm", size / 1000000)
    elseif size >= 1000 then
        return string.format("%.1fk", size / 1000)
    end
    return tostring(size)
end

function ContextSizeCommand:execute(args)
    local current_size = config.context_size()
    
    if not args or #args == 0 then
        -- Show current status
        log.print(string.format("Current context size: %s tokens (%d)", format_size(current_size), current_size))
        log.dim("Usage: /cs <size> | Examples: /cs 100k, /cs 1.5m, /cs 50000")
        return CommandResult.new(false, false)
    end
    
    local value = args[1]
    local new_size
    
    local ok, err = pcall(function()
        new_size = parse_size(value)
    end)
    
    if not ok or not new_size then
        log.error("Invalid size format. Use: 100k, 1.5m, 50000, or 'default'")
        return CommandResult.new(false, false)
    end
    
    -- Validate range
    if new_size < 1000 then
        log.error("Context size too small. Minimum: 1k (1000 tokens)")
        return CommandResult.new(false, false)
    end
    
    if new_size > 10000000 then
        log.error("Context size too large. Maximum: 10m (10,000,000 tokens)")
        return CommandResult.new(false, false)
    end
    
    -- Set new size
    local old_size = current_size
    config.set_context_size(new_size)
    
    -- Notify plugins of context size change
    if self.context.plugin_system then
        self.context.plugin_system:call_hooks("on_context_size_changed", new_size)
    end
    
    -- Show confirmation
    log.success(string.format("Context size changed: %s → %s", format_size(old_size), format_size(new_size)))
    
    -- Recalculate context estimate
    if self.context.message_history then
        self.context.message_history:estimate_context()
    end
    
    return CommandResult.new(false, false)
end

return ContextSizeCommand
