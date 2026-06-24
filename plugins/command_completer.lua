-- Command Completer Plugin - Tab completion for /commands
-- Ported from Python command_completer.py
--
-- Features:
-- - Tab completion with / prefix
-- - Includes all registered commands (built-in and plugin)
-- - Includes command aliases

local M = {}

function M.create_plugin(self, ctx)
    -- Separate table to store matches across completer calls (Lua functions can't have attributes)
    local _completion_state = {
        matches = {}
    }

    local function command_completer(text, state)
        -- Only activate for / prefix
        if not text:match("^/") then
            return nil
        end

        if state == 0 then
            local options = {}

            -- Get all commands from command_handler
            if ctx.app and ctx.app.command_handler then
                local commands = ctx.app.command_handler:get_all_commands()

                -- Add primary commands with / prefix
                for cmd_name, _ in pairs(commands) do
                    table.insert(options, "/" .. cmd_name)
                end

                -- Add aliases with / prefix (skip duplicates)
                local aliases = ctx.app.command_handler.aliases
                if aliases then
                    for alias, _ in pairs(aliases) do
                        if not commands[alias] then
                            table.insert(options, "/" .. alias)
                        end
                    end
                end
            end

            -- Filter commands that match the prefix
            local filtered = {}
            for _, cmd in ipairs(options) do
                if cmd:sub(1, #text) == text then
                    table.insert(filtered, cmd)
                end
            end
            table.sort(filtered)

            -- Store for iteration
            _completion_state.matches = filtered
        end

        -- Return the appropriate match based on state
        if state < #_completion_state.matches then
            return _completion_state.matches[state + 1]
        end
        return nil
    end

    -- Register completer
    ctx:register_completer(command_completer)

    -- No cleanup needed
    return nil
end

return M
