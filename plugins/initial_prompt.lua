-- Plugin: initial_prompt
--
-- Reads AICODER_INITIAL_PROMPT env var and sends it automatically at startup.
-- No user input needed - the prompt fires immediately.
--
-- Usage:
--     export AICODER_INITIAL_PROMPT="Explain this video thoroughly"
--     aicoder
--     # AI responds immediately with explanation

local config = require("core.config")

local _initial_prompt_sent = false

local M = {}

function M:create_plugin(ctx)
    local function inject_initial_prompt()
        if _initial_prompt_sent then
            return
        end

        local initial = os.getenv("AICODER_INITIAL_PROMPT")
        if not initial or initial == "" then
            return
        end

        initial = initial:match("^%s*(.-)%s*$")  -- trim
        if initial == "" then
            return
        end

        _initial_prompt_sent = true
        local c = config.colors
        print("\n" .. c.cyan .. "[initial_prompt] Injecting first message: " .. initial .. c.reset)
        -- Set as next prompt - will be used instead of waiting for user input
        ctx.app:set_next_prompt(initial)
    end

    ctx:register_hook("before_user_prompt", inject_initial_prompt)
end

return M
