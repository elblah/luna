-- Edit session command - Export conversation JSON to temp file, edit with $EDITOR, then reload
-- Renamed from memory.lua to free up /memory for memory plugin

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local temp_file_utils = require("utils.temp_file_utils")
local json = require("utils.json")

local EditSessionCommand = setmetatable({}, BaseCommand.BaseCommand)
EditSessionCommand.__index = EditSessionCommand

function EditSessionCommand.new(context)
    local self = setmetatable({}, EditSessionCommand)
    self.context = context
    self._name = "edit-session"
    self._description = "Edit session JSON in $EDITOR"
    return self
end

function EditSessionCommand:get_name()
    return self._name
end

function EditSessionCommand:get_description()
    return self._description
end

function EditSessionCommand:get_aliases()
    return {"es"}
end

function EditSessionCommand:execute(args)
    local message_history = self.context.message_history

    -- Get non-system messages (consistent with session persistence)
    local messages = message_history:get_session_messages() or {}
    if #messages == 0 then
        log.warn("No messages in session")
        return CommandResult.new(false, false)
    end

    -- Create temp file
    local temp_file = temp_file_utils.create_temp_file("aicoder-memory", ".json")

    -- Write JSON to temp file
    local json_str = json.encode(messages)
    local f = io.open(temp_file, "w")
    if not f then
        log.error("Failed to create temp file: " .. temp_file)
        return CommandResult.new(false, false)
    end
    f:write(json_str)
    f:close()

    -- Format JSON with fallback: gojq -> jq -> python3
    local fmt_cmd
    local check = io.popen("which gojq 2>/dev/null")
    if check then
        local result = check:read("*all")
        check:close()
        if result and result ~= "" then
            fmt_cmd = "gojq . " .. temp_file .. " > " .. temp_file .. ".fmt 2>/dev/null"
        end
    end
    if not fmt_cmd then
        check = io.popen("which jq 2>/dev/null")
        if check then
            local result = check:read("*all")
            check:close()
            if result and result ~= "" then
                fmt_cmd = "jq . " .. temp_file .. " > " .. temp_file .. ".fmt 2>/dev/null"
            end
        end
    end
    if not fmt_cmd then
        fmt_cmd = "python3 -m json.tool " .. temp_file .. " > " .. temp_file .. ".fmt 2>/dev/null"
    end

    os.execute(fmt_cmd .. " && mv " .. temp_file .. ".fmt " .. temp_file .. " 2>/dev/null")

    log.info("Exported " .. #messages .. " messages to " .. temp_file)
    log.info("Opening $EDITOR...")

    -- Open editor (blocks until closed, like edit.lua)
    local editor = os.getenv("EDITOR") or "nano"
    os.execute(editor .. " " .. temp_file)

    -- Read edited content
    local check = io.open(temp_file, "r")
    if not check then
        log.error("Session file not found after editing")
        return CommandResult.new(false, false)
    end

    local edited_content = check:read("*all")
    check:close()

    -- Parse JSON
    local ok, edited_messages = pcall(json.decode, edited_content)
    if not ok then
        log.error("Invalid JSON in session file")
        temp_file_utils.delete_file(temp_file)
        return CommandResult.new(false, false)
    end

    if type(edited_messages) ~= "table" then
        log.error("Invalid session file format - expected array")
        temp_file_utils.delete_file(temp_file)
        return CommandResult.new(false, false)
    end

    -- Preserve current system prompt, replace rest (like load.lua)
    local current_messages = message_history:get_messages()
    local system_msg = nil
    for _, msg in ipairs(current_messages) do
        if msg.role == "system" then
            system_msg = msg
            break
        end
    end

    if system_msg then
        local new_messages = {system_msg}
        for _, msg in ipairs(edited_messages) do
            if msg.role ~= "system" then
                table.insert(new_messages, msg)
            end
        end
        message_history:set_messages(new_messages)
    else
        message_history:set_messages(edited_messages)
    end

    log.success("Reloaded " .. #edited_messages .. " messages from editor")
    log.dim("System prompt preserved (not shown/editable)")

    -- Clean up temp file
    temp_file_utils.delete_file(temp_file)

    return CommandResult.new(false, false)
end

return EditSessionCommand
