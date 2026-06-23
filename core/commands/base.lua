-- Base command interface
-- Ported from Python commands/base.py

local M = {}

-- Command context provided to commands
local CommandContext = {}
CommandContext.__index = CommandContext

function CommandContext.new(message_history, input_handler, stats, plugin_system, command_handler)
    local self = setmetatable({}, CommandContext)
    self.message_history = message_history
    self.input_handler = input_handler
    self.stats = stats
    self.plugin_system = plugin_system
    self.command_handler = command_handler
    return self
end

M.CommandContext = CommandContext

-- Command result
local CommandResult = {
    should_quit = false,
    run_api_call = true,
    message = nil,
    command_to_execute = nil,
}
CommandResult.__index = CommandResult

function CommandResult.new(should_quit, run_api_call, message, command_to_execute)
    local self = setmetatable({}, CommandResult)
    self.should_quit = should_quit or false
    self.run_api_call = run_api_call ~= false  -- default true
    self.message = message
    self.command_to_execute = command_to_execute
    return self
end

M.CommandResult = CommandResult

-- Base command class
local BaseCommand = {}
BaseCommand.__index = BaseCommand

function BaseCommand.new(context)
    local self = setmetatable({}, BaseCommand)
    self.context = context
    return self
end

function BaseCommand:get_name()
    -- Abstract method
    return "base"
end

function BaseCommand:get_description()
    -- Abstract method
    return ""
end

function BaseCommand:execute(args)
    -- Abstract method
    return CommandResult.new()
end

function BaseCommand:get_aliases()
    return {}
end

-- Get all available commands (parity with Python's BaseCommand.get_all_commands)
-- In Lua, commands are discovered via the registry, but we expose this
-- method on the class for parity. Returns a table mapping name -> command instance.
function BaseCommand.get_all_commands()
    local ok, registry = pcall(require, "core.commands.registry")
    if not ok or not registry then
        return {}
    end
    if type(registry.get_all_commands) == "function" then
        return registry.get_all_commands()
    end
    return {}
end

M.BaseCommand = BaseCommand

-- ABC stub for 1-1 parity with Python's CommandHandler interface
local CommandHandler = {}
CommandHandler.__index = CommandHandler
function CommandHandler:get_all_commands()
    -- Implemented by subclass (CommandRegistry in registry.lua)
    return {}
end
M.CommandHandler = CommandHandler

return M
