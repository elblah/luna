-- Quit command implementation
-- Ported from Python commands/quit.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")

local QuitCommand = setmetatable({}, BaseCommand.BaseCommand)
QuitCommand.__index = QuitCommand

function QuitCommand.new(context)
    local self = setmetatable({}, QuitCommand)
    self.context = context
    self._name = "quit"
    self._description = "Exit the application"
    return self
end

function QuitCommand:get_name()
    return self._name
end

function QuitCommand:get_description()
    return self._description
end

function QuitCommand:get_aliases()
    return {"q"}
end

function QuitCommand:execute(args)
    log.success("Goodbye!")
    return CommandResult.new(true, false)
end

return QuitCommand
