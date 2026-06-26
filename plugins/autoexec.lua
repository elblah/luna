-- Plugin: autoexec
-- Execute .aicoder/autoexec line by line at startup
--
-- Each line is fed as the next prompt. The main loop handles commands/prompts.
--
-- Example .aicoder/autoexec:
--   /cs 100k
--   /detail on
--   hello my name is Blah

local config = require("core.config")

local _AUTOEXEC_FILE = ".aicoder/autoexec"

local M = {}

function M:create_plugin(ctx)
    local lines = {}
    local started = false

    local function feed_next()
        if not started then
            started = true
            local f = io.open(_AUTOEXEC_FILE, "r")
            if not f then return end

            for line in f:lines() do
                line = line:match("^%s*(.-)%s*$")  -- trim
                if line and line ~= "" and not line:match("^#") then
                    -- Strip inline comments ("foo # bar" -> "foo")
                    local idx = line:find(" #")
                    if idx then
                        line = line:sub(1, idx - 1)
                        line = line:match("^%s*(.-)%s*$")
                    end
                    if line and line ~= "" then
                        table.insert(lines, line)
                    end
                end
            end
            f:close()

            if #lines == 0 then return end

            local c = config.colors
            print("\n" .. c.cyan .. "[autoexec] " .. #lines .. " line(s)" .. c.reset)

            local next_line = table.remove(lines, 1)
            print(c.cyan .. "[autoexec] " .. next_line .. c.reset)
            ctx.app:set_next_prompt(next_line)
            return
        end

        -- Subsequent calls: feed next line if any
        if #lines == 0 then return end

        local c = config.colors
        local next_line = table.remove(lines, 1)
        print("\n" .. c.cyan .. "[autoexec] " .. next_line .. c.reset)
        ctx.app:set_next_prompt(next_line)
    end

    ctx:register_hook("before_user_prompt", feed_next)
end

return M
