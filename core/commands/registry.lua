-- Command registry implementation
-- Ported from Python commands/registry.py
-- 1-1 parity file: functionality is exposed via core.command_handler

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")

local M = {}

-- Check if exception is a quit type (BdbQuit, SystemExit) - for parity with Python
local function is_quit_exception(_)
    -- LuaJIT has no BdbQuit; pcall SystemExit/quit can be raised manually
    return false
end

-- Expose as module-level for parity with Python's _is_quit_exception
M._is_quit_exception = is_quit_exception

-- SimplePluginCommand - wrapper for simple plugin command functions
local SimplePluginCommand = {}
SimplePluginCommand.__index = SimplePluginCommand

function SimplePluginCommand.new(name, handler, description)
    local self = setmetatable({}, SimplePluginCommand)
    self.name = name
    self.handler = handler
    self.description = description or ("Plugin command: " .. name)
    return self
end

function SimplePluginCommand:get_name()
    return self.name
end

function SimplePluginCommand:get_description()
    return self.description
end

function SimplePluginCommand:get_aliases()
    return {}
end

function SimplePluginCommand:execute(args)
    local ok, result = pcall(self.handler, args or "")
    if ok and result then
        log.print(result)
    elseif not ok and not is_quit_exception(result) then
        log.error("Error executing command: " .. tostring(result))
    end
    return CommandResult.new(false, false)
end

M.SimplePluginCommand = SimplePluginCommand

-- CommandRegistry - registry for all commands
local CommandRegistry = {}
CommandRegistry.__index = CommandRegistry

function CommandRegistry.new(context)
    local self = setmetatable({}, CommandRegistry)
    self.context = context
    self.commands = {}
    self.aliases = {}
    self:_register_all_commands()
    return self
end

function CommandRegistry:_register_all_commands()
    local commands = {
        {name = "help", module = require("core.commands.help")},
        {name = "quit", module = require("core.commands.quit")},
        {name = "stats", module = require("core.commands.stats")},
        {name = "save", module = require("core.commands.save")},
        {name = "load", module = require("core.commands.load")},
        {name = "compact", module = require("core.commands.compact")},
        {name = "sandbox", module = require("core.commands.sandbox")},
        {name = "edit", module = require("core.commands.edit")},
        {name = "retry", module = require("core.commands.retry")},
        {name = "memory", module = require("core.commands.memory")},
        {name = "yolo", module = require("core.commands.yolo")},
        {name = "detail", module = require("core.commands.detail")},
        {name = "new", module = require("core.commands.new")},
        {name = "debug", module = require("core.commands.debug")},
        {name = "thinking", module = require("core.commands.thinking")},
        {name = "context-size", module = require("core.commands.context_size")},
    }
    for _, cmd in ipairs(commands) do
        self:register_command(cmd.module.new(self.context))
    end
end

function CommandRegistry:register_command(command)
    local name = command:get_name()
    self.commands[name] = command
    local aliases = command:get_aliases() or {}
    for _, alias in ipairs(aliases) do
        self.aliases[alias] = name
    end
end

function CommandRegistry:get_command(name)
    local actual_name = self.aliases[name] or name
    return self.commands[actual_name]
end

function CommandRegistry:get_all_commands()
    local copy = {}
    for k, v in pairs(self.commands) do copy[k] = v end
    return copy
end

function CommandRegistry:register_simple_command(name, handler, description)
    name = (name or ""):gsub("^/", "")
    local cmd = SimplePluginCommand.new(name, handler, description)
    self.commands[name] = cmd
end

function CommandRegistry:list_commands()
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

function CommandRegistry:execute_command(command_line)
    command_line = (command_line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if command_line == "" then
        return CommandResult.new(false, false)
    end
    local parts = {}
    for p in command_line:gmatch("%S+") do table.insert(parts, p) end
    local cmd_name = parts[1]:gsub("^/", "")
    local args = {}
    for i = 2, #parts do table.insert(args, parts[i]) end
    local command = self:get_command(cmd_name)
    if not command then
        log.error("Unknown command: " .. command_line)
        return CommandResult.new(false, false)
    end
    local ok, result = pcall(function() return command:execute(args) end)
    if not ok then
        if not is_quit_exception(result) then
            log.error("Error executing command: " .. tostring(result))
        end
        return CommandResult.new(false, false)
    end
    return result
end

M.CommandRegistry = CommandRegistry
M.new = CommandRegistry.new

return M
