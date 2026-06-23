-- Load command implementation
-- Ported from Python commands/load.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")

local LoadCommand = setmetatable({}, BaseCommand.BaseCommand)
LoadCommand.__index = LoadCommand

function LoadCommand.new(context)
    local self = setmetatable({}, LoadCommand)
    self.context = context
    self._name = "load"
    self._description = "Load session from file"
    return self
end

function LoadCommand:get_name()
    return self._name
end

function LoadCommand:get_description()
    return self._description
end

function LoadCommand:get_aliases()
    return {"l"}
end

function LoadCommand:execute(args)
    local filename = nil

    if args and #args > 0 then
        filename = args[1]
    end

    -- Helper: find last session file
    local function find_last_session()
        local f = io.open("last", "r")
        if f then
            f:close()
            return "last"
        end
        f = io.open(".aicoder/last-session.json", "r")
        if f then
            f:close()
            return ".aicoder/last-session.json"
        end
        return nil
    end

    -- Helper: check if file exists
    local function file_exists(path)
        local f = io.open(path, "r")
        if f then
            f:close()
            return true
        end
        return false
    end

    -- Handle no args: prefer session.json if exists, else load last
    if filename == nil then
        local session_exists = file_exists("session.json")
        local last_exists = file_exists("last") or file_exists(".aicoder/last-session.json")

        if session_exists and last_exists then
            log.error("Both session.json and last-session.json exist. Use '/load session.json' or '/load last' to specify.")
            return CommandResult.new(false, false)
        elseif session_exists then
            filename = "session.json"
        else
            filename = find_last_session()
            if not filename then
                log.error("No session file found (session.json or last-session.json)")
                return CommandResult.new(false, false)
            end
        end
    -- Handle /load last or /load l (load most recent session)
    elseif filename == "last" or filename == "l" then
        filename = find_last_session()
        if not filename then
            log.error("No 'last' file found in current directory or .aicoder/last-session.json")
            return CommandResult.new(false, false)
        end
    end

    -- Call session change hooks
    if self.context.plugin_system then
        self.context.plugin_system:call_hooks("on_session_change")
    end

    local f = io.open(filename, "r")
    if not f then
        log.error("Session file not found: " .. filename)
        return CommandResult.new(false, false)
    end

    local content = f:read("*all")
    f:close()

    local json = require("utils.json")
    local decode_ok, session_data = pcall(json.decode, content)
    if not decode_ok then
        log.error("Invalid JSON in session file")
        return CommandResult.new(false, false)
    end

    -- Handle both formats: direct array or object with messages property
    local messages
    if type(session_data) == "table" and session_data.messages then
        messages = session_data.messages
    else
        messages = session_data
    end

    if type(messages) == "table" then
        self.context.message_history:set_messages(messages)
        log.success("Session loaded from " .. filename)
    else
        log.error("Invalid session file format")
    end

    return CommandResult.new(false, false)
end

return LoadCommand