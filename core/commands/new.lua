-- New command - Reset the entire session
-- Ported from Python commands/new.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")

local NewCommand = setmetatable({}, BaseCommand.BaseCommand)
NewCommand.__index = NewCommand

function NewCommand.new(context)
    local self = setmetatable({}, NewCommand)
    self.context = context
    self._name = "new"
    self._description = "Reset the entire session"
    return self
end

function NewCommand:get_name()
    return self._name
end

function NewCommand:get_description()
    return self._description
end

function NewCommand:get_aliases()
    return {"n"}
end

function NewCommand:execute(args)
    -- Call session change hooks before clearing
    if self.context.plugin_system then
        self.context.plugin_system:call_hooks("on_session_change")
    end

    -- Clear message history
    self.context.message_history:clear()

    log.success("Session reset. Starting fresh.")
    return CommandResult.new(false, false)
end

return NewCommand
