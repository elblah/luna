-- Help command implementation
-- Ported from Python commands/help.py

local BaseCommand = require("core.commands.base")
local CommandResult = BaseCommand.CommandResult
local config = require("core.config")
local log = require("utils.log")

local HelpCommand = setmetatable({}, BaseCommand.BaseCommand)
HelpCommand.__index = HelpCommand

function HelpCommand.new(context)
    local self = setmetatable({}, HelpCommand)
    self.context = context
    self._name = "help"
    self._description = "Show this help message"
    return self
end

function HelpCommand:get_name()
    return self._name
end

function HelpCommand:get_description()
    return self._description
end

function HelpCommand:get_aliases()
    return {"?", "h"}
end

function HelpCommand:execute(args)
    local command_handler = self.context.command_handler
    if not command_handler then
        log.error("Error: Command handler not available")
        return CommandResult.new(false, false)
    end

    local show_all = false
    if args then
        for _, arg in ipairs(args) do
            if arg == "all" or arg == "--all" then
                show_all = true
                break
            end
        end
    end

    local commands = command_handler:get_all_commands()
    local command_names = {}
    for name, _ in pairs(commands) do
        table.insert(command_names, name)
    end

    -- Sort commands alphabetically (skip help itself)
    table.sort(command_names, function(a, b)
        if a == "help" then return false end
        if b == "help" then return true end
        return a < b
    end)

    -- Build command entries
    local command_entries = {}
    local max_width = 0

    -- Helper to get aliases string
    local function get_aliases_str(aliases)
        if not aliases or #aliases == 0 then
            return ""
        end
        local alias_list = {}
        for _, alias in ipairs(aliases) do
            table.insert(alias_list, "/" .. alias)
        end
        return " (alias: " .. table.concat(alias_list, ", ") .. ")"
    end

    -- Add help command entry
    local help_aliases = self:get_aliases()
    local help_alias_str = get_aliases_str(help_aliases)
    local help_entry = {
        name = self:get_name(),
        alias_str = help_alias_str,
        description = self:get_description(),
    }
    table.insert(command_entries, help_entry)
    local help_width = #("/" .. help_entry.name .. help_entry.alias_str)
    max_width = math.max(max_width, help_width)

    -- Add all other commands (skip "help" to avoid duplicates)
    for _, name in ipairs(command_names) do
        if name == "help" then
            goto continue
        end
        local command = commands[name]
        if not command then
            goto continue
        end

        local cmd_name = name
        if command.get_name and type(command.get_name) == "function" then
            cmd_name = command:get_name()
        end

        local description = "Unknown command"
        if command.get_description and type(command.get_description) == "function" then
            description = command:get_description()
        end

        local aliases = {}
        if command.get_aliases and type(command.get_aliases) == "function" then
            aliases = command:get_aliases()
        end

        local alias_str = get_aliases_str(aliases)
        local entry = {
            name = cmd_name,
            alias_str = alias_str,
            description = description,
        }
        table.insert(command_entries, entry)

        local width = #("/" .. entry.name .. entry.alias_str)
        max_width = math.max(max_width, width)

        ::continue::
    end

    -- Sort all entries alphabetically
    table.sort(command_entries, function(a, b)
        return a.name < b.name
    end)

    -- Format command lines with aligned dashes
    local command_lines = {}
    local green = config.colors and config.colors.green or ""
    local bold = config.colors and config.colors.bold or ""
    local reset = config.colors and config.colors.reset or ""

    for _, entry in ipairs(command_entries) do
        local cmd_full = "/" .. entry.name .. entry.alias_str
        local padding = string.rep(" ", max_width - #cmd_full + 2)
        local line = string.format("  %s%s%s%s  -  %s%s",
            green, cmd_full, reset, padding, bold, entry.description)
        table.insert(command_lines, line)
    end

    local command_list = table.concat(command_lines, "\n")

    local help_text = string.format("\n%sAvailable Commands:%s\n\n%s",
        bold .. green, reset, command_list)

    print(help_text)

    -- Show environment configuration help only when requested with "all"
    if show_all then
        print()
        print(bold .. "Environment Configuration:" .. reset)
        print()
        print("[!] Error: Missing required environment variable:")
        print("[!]   - API_BASE_URL or OPENAI_BASE_URL")
        print()
        print("[*] Example configuration:")
        print('[+]   export API_BASE_URL="https://your-api-provider.com/v1"')
        print()
        print("Optional variables:")
        print('[+]   export API_KEY="your-api-key-here" (optional, some providers don\'t require it)')
        print('[+]   export API_MODEL="your-model-name" (optional, some providers have a default)')
        print("[*]   export TEMPERATURE=0.0")
        print("[*]   export MAX_TOKENS=4096")
        print("[*]   export DEBUG=1")
        print('[+]   export AICODER_SYSTEM_PROMPT="your-custom-prompt"')
        print('[+]   export AICODER_SYSTEM_PROMPT_APPEND="additional-instructions"')
        print()
        print("  Anthropic Provider:")
        print("    API_PROVIDER=anthropic")
        print("    API_ENDPOINT     Anthropic-compatible endpoint")
        print('                   Example: export API_ENDPOINT="https://api.minimax.io/anthropic/v1/messages"')
    end

    print()
    print(bold .. "Tip:" .. reset .. " Use /<command> --help for detailed help on a specific command, /help all for environment info")

    return CommandResult.new(false, false)
end

return HelpCommand
