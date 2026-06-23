-- Command Handler for Luna
-- Ported from Python command_handler.py with command registry pattern

local log = require("utils.log")
local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult

local CommandHandler = {}
CommandHandler.__index = CommandHandler

function CommandHandler.new(message_history, input_handler, stats, plugin_system)
    local self = setmetatable({}, CommandHandler)
    self.context = {
        message_history = message_history,
        input_handler = input_handler,
        stats = stats,
        plugin_system = plugin_system,
        command_handler = self,
    }
    self.commands = {}
    self.aliases = {}
    self:register_all_commands()
    return self
end

function CommandHandler:register_all_commands()
    -- Delegate to CommandRegistry for 1-1 parity with Python
    local registry = require("core.commands.registry")
    local reg = registry.CommandRegistry.new(self.context)
    -- Copy commands and aliases from registry
    for name, command in pairs(reg:get_all_commands()) do
        self.commands[name] = command
    end
    for alias, name in pairs(reg.aliases) do
        self.aliases[alias] = name
    end
end

function CommandHandler:register_command(command)
    local name = command:get_name()
    self.commands[name] = command

    -- Register aliases
    local aliases = command:get_aliases()
    if aliases then
        for _, alias in ipairs(aliases) do
            self.aliases[alias] = name
        end
    end
end

function CommandHandler:get_command(name)
    local actual_name = self.aliases[name] or name
    local cmd = self.commands[actual_name]
    if cmd then return cmd end
    -- Check plugin commands
    if self.plugin_system and self.plugin_system.commands then
        return self.plugin_system.commands[actual_name]
    end
    return nil
end

function CommandHandler:get_all_commands()
    return self.commands
end

-- Simple command registration for plugins (no class needed)
function CommandHandler:register_simple_command(name, fn, description)
    -- Strip leading slash for storage
    local stored_name = name:gsub("^/", "")
    local simple_cmd = {
        get_name = function() return stored_name end,
        get_description = function() return description or "" end,
        get_aliases = function() return {} end,
        execute = function(_, args)
            -- Handle args as either table or string
            local args_str
            if type(args) == "table" then
                args_str = table.concat(args, " ")
            else
                args_str = args or ""
            end
            local result = fn(args_str)
            if result then
                print(result)
            end
            return CommandResult.new(false, false)
        end
    }
    self:register_command(simple_cmd)
end

function CommandHandler:handle_command(command_line)
    command_line = command_line:gsub("^%s+", ""):gsub("%s+$", "")

    local parts = {}
    for part in command_line:gmatch("%S+") do
        table.insert(parts, part)
    end

    if #parts == 0 then
        return {should_quit = false, run_api_call = false}
    end

    local command_name = parts[1]:gsub("^/", "")
    local args = {}
    for i = 2, #parts do
        table.insert(args, parts[i])
    end

    local command = self:get_command(command_name)
    if not command then
        log.error("Unknown command: " .. command_name)
        return {should_quit = false, run_api_call = false}
    end

    local ok, result = pcall(function()
        -- Plugin commands have fn field, commands have execute method
        if command.fn then
            return command.fn(args)
        else
            return command:execute(args)
        end
    end)

    if not ok then
        log.error("Error executing command: " .. tostring(result))
        return {should_quit = false, run_api_call = false}
    end

    return result
end

-- List all commands with their descriptions
function CommandHandler:list_commands()
    local result = {}
    for _, cmd in pairs(self.commands) do
        table.insert(result, {
            name = cmd:get_name(),
            description = cmd:get_description() or "",
            aliases = cmd:get_aliases() or {},
        })
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- Execute a command from a full command line
function CommandHandler:execute_command(command_line)
    command_line = (command_line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if command_line == "" then
        return CommandResult.new(false, false)
    end
    return self:handle_command(command_line)
end

return CommandHandler
