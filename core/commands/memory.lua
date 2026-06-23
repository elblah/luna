-- Memory command - Export conversation JSON to temp file, edit with $EDITOR, then reload
-- Ported from Python commands/memory.py
-- Requires tmux environment

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local log = require("utils.log")
local temp_file_utils = require("utils.temp_file_utils")
local json = require("utils.json")

local MemoryCommand = setmetatable({}, BaseCommand.BaseCommand)
MemoryCommand.__index = MemoryCommand

-- Generate random hex token
local function _gen_token()
    math.randomseed(os.time() + os.clock() * 1000000)
    return string.format("%08x", math.random(0, 0xFFFFFFFF))
end

function MemoryCommand.new(context)
    local self = setmetatable({}, MemoryCommand)
    self.context = context
    self._name = "memory"
    self._description = "Edit conversation memory in $EDITOR"
    return self
end

function MemoryCommand:get_name()
    return self._name
end

function MemoryCommand:get_description()
    return self._description
end

function MemoryCommand:get_aliases()
    return {"m"}
end

function MemoryCommand:execute(args)
    local message_history = self.context.message_history
    
    -- Check if in tmux
    if not os.getenv("TMUX") then
        log.error("This command only works inside a tmux environment.")
        log.warn("Please run this command inside tmux.")
        return CommandResult.new(false, false)
    end
    
    -- Get messages
    local messages = message_history.messages or {}
    
    -- Create temp file
    local random_suffix = _gen_token()
    local temp_file = temp_file_utils.create_temp_file("aicoder-memory-" .. random_suffix, ".json")
    
    -- Write JSON to temp file
    local json_str = json.encode(messages)
    local f = io.open(temp_file, "w")
    if not f then
        log.error("Failed to create temp file: " .. temp_file)
        return CommandResult.new(false, false)
    end
    f:write(json_str)
    f:close()
    
    -- Format JSON with fallback: gojq -> jq -> python
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
    log.info("Opening $EDITOR in tmux window...")
    log.dim("Save and exit when done. The editor is running in a separate tmux window.")
    
    -- Get editor
    local editor = os.getenv("EDITOR") or "nano"
    
    -- Use tmux wait-for sync
    local sync_point = "memory_done_" .. random_suffix
    local window_name = "memory_" .. random_suffix
    
    local tmux_new = 'tmux new-window -n "' .. window_name .. '" \'bash -c "' .. editor .. " " .. temp_file .. "; tmux wait-for -S " .. sync_point .. '"\''
    
    local handle = io.popen(tmux_new)
    if not handle then
        log.error("Failed to execute tmux command")
        return CommandResult.new(false, false)
    end
    handle:close()
    
    -- Wait for sync point
    local wait_cmd = "tmux wait-for " .. sync_point
    handle = io.popen(wait_cmd)
    if not handle then
        log.error("tmux wait-for failed")
        return CommandResult.new(false, false)
    end
    handle:close()
    
    -- Check if file still exists
    local check = io.open(temp_file, "r")
    if not check then
        log.error("Session file not found after editing")
        return CommandResult.new(false, false)
    end
    
    -- Read edited content
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
    
    -- Replace messages
    message_history.messages = edited_messages
    
    log.success("Reloaded " .. #edited_messages .. " messages from editor")
    
    -- Clean up temp file
    temp_file_utils.delete_file(temp_file)
    
    return CommandResult.new(false, false)
end

return MemoryCommand
