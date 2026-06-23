-- Edit command implementation
-- Requires tmux environment

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")

local EditCommand = setmetatable({}, BaseCommand.BaseCommand)
EditCommand.__index = EditCommand

function EditCommand.new(context)
    local self = setmetatable({}, EditCommand)
    self.context = context
    self._name = "edit"
    self._description = "Create new message in $EDITOR"
    return self
end

function EditCommand:get_name()
    return self._name
end

function EditCommand:get_description()
    return self._description
end

function EditCommand:get_aliases()
    return {"e"}
end

function EditCommand:execute(args)
    local os = require("os")
    local temp_utils = require("utils.temp_file_utils")
    local temp_file = temp_utils.create_temp_file("aicoder-edit", ".md")

    -- Get initial content
    local initial_content = ""
    if args and #args > 0 then
        if args[1] == "last" then
            -- Get last user message
            local messages = self.context.message_history.get_messages()
            for i = #messages, 1, -1 do
                local msg = messages[i]
                if msg.role == "user" then
                    initial_content = type(msg.content) == "string" and msg.content or (msg.content and msg.content.text) or ""
                    break
                end
            end
        else
            -- Use args as initial content
            initial_content = table.concat(args, " ")
            log.info("Pre-populating with input text...")
        end
    end

    -- Write to temp file
    local f = io.open(temp_file, "w")
    if not f then
        log.error("Could not create temp file")
        return CommandResult.new(false, false)
    end
    f:write(initial_content)
    f:close()

    -- Open editor
    local editor = os.getenv("EDITOR") or "vim"
    log.info("Opening " .. editor .. "...")
    
    os.execute(editor .. " " .. temp_file)

    -- Read result
    f = io.open(temp_file, "r")
    if not f then
        log.error("Could not read temp file")
        return CommandResult.new(false, false)
    end
    local content = f:read("*all")
    f:close()
    os.remove(temp_file)

    if content == "" or not content then
        log.warn("Empty message - cancelled.")
        return CommandResult.new(false, false)
    end

    -- Remove trailing whitespace
    content = content:gsub("%s+$", "")

    if content == "" then
        log.warn("Empty message - cancelled.")
        return CommandResult.new(false, false)
    end

    -- Check if command
    local trimmed = content:match("^%s*(.-)%s*$")
    if trimmed and trimmed:sub(1, 1) == "/" then
        log.success("Command composed.")
        log.info("--- Command ---")
        print(content)
        log.info("---------------")
        return CommandResult.new(false, false, nil, content)
    end

    log.success("Message composed.")
    log.info("--- Message ---")
    print(content)
    log.info("---------------")
    return CommandResult.new(false, true, content, nil)
end

return EditCommand
