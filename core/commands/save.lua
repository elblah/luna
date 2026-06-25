-- Save command implementation
-- Ported from Python commands/save.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")

local SaveCommand = setmetatable({}, BaseCommand.BaseCommand)
SaveCommand.__index = SaveCommand

function SaveCommand.new(context)
    local self = setmetatable({}, SaveCommand)
    self.context = context
    self._name = "save"
    self._description = "Save current session to file"
    return self
end

function SaveCommand:get_name()
    return self._name
end

function SaveCommand:get_description()
    return self._description
end

function SaveCommand:get_aliases()
    return {"s"}
end

function SaveCommand:execute(args)
    local filename = "session.json"
    if args and #args > 0 then
        filename = args[1]
    end

    local messages = self.context.message_history:get_session_messages()

    -- Only save if there's at least one real user message or assistant message
    local has_real_content = false
    for _, msg in ipairs(messages) do
        local role = msg.role
        local content = msg.content
        if (role == "user" or role == "assistant") and content and content ~= "" then
            has_real_content = true
            break
        end
    end

    if not has_real_content then
        log.info("Skipping save to " .. filename .. ": no real user or assistant messages in session")
        return CommandResult.new(false, false)
    end

    local json = require("utils.json")

    -- Detect format based on file extension
    local is_jsonl = filename:match("%.jsonl$") ~= nil

    local ok, err
    if is_jsonl then
        -- Save in JSONL format
        local f, open_err = io.open(filename, "w")
        if not f then
            log.error("Error saving session: " .. tostring(open_err))
            return CommandResult.new(false, false)
        end
        for _, msg in ipairs(messages) do
            f:write(json.encode(msg) .. "\n")
        end
        f:close()
        log.success("Session saved to " .. filename .. " (JSONL format)")
    else
        -- Save in JSON format
        local f, open_err = io.open(filename, "w")
        if not f then
            log.error("Error saving session: " .. tostring(open_err))
            return CommandResult.new(false, false)
        end
        local encode_ok, encoded = pcall(function() return json.encode(messages) end)
        if not encode_ok then
            log.error("Error encoding session: " .. tostring(encoded))
            f:close()
            return CommandResult.new(false, false)
        end
        f:write(encoded)
        f:close()
        log.success("Session saved to " .. filename .. " (JSON format)")
    end

    return CommandResult.new(false, false)
end

return SaveCommand
