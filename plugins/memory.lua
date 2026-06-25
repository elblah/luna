-- Plugin: memory
-- Auto-managed persistent memory for cross-session learning.
--
-- Creates .aicoder/memory/ structure:
--   autoload.md - auto-injected into system prompt (max 2KB)
--   index.md - main memory file, AI manages freely
--   *.md - any additional files AI creates
--
-- The AI uses write_file/edit_file tools to manage memory naturally.
-- No special API calls or background processes needed.

local config = require("core.config")
local log = require("utils.log")

local MEMORY_DIR = ".aicoder/memory"
local AUTOLOAD_FILE = MEMORY_DIR .. "/autoload.md"
local INDEX_FILE = MEMORY_DIR .. "/index.md"
local MAX_AUTOLOAD_BYTES = 2048
local AUTOLOAD_DISABLED = AUTOLOAD_FILE .. ".disabled"

local _pending_check = {}  -- autoload.md paths to check after tool results
local _app = nil

local M = {}

function M:create_plugin(ctx)
    _app = ctx.app
    local function get_autoload()
        local f = io.open(AUTOLOAD_FILE, "r")
        if not f then return nil end
        local content = f:read("*all")
        f:close()
        if not content or #content == 0 then return nil end
        if #content > MAX_AUTOLOAD_BYTES then
            log.warn("[memory] autoload.md truncated (" .. #content .. " bytes, max " .. MAX_AUTOLOAD_BYTES .. ")")
            -- Truncate and append note so AI knows it was cut
            local trunc_note = "\n\n[... truncated to " .. MAX_AUTOLOAD_BYTES .. " bytes ...]"
            content = content:sub(1, MAX_AUTOLOAD_BYTES - #trunc_note) .. trunc_note
        end
        return content
    end

    -- Queue autoload.md for size check after write/edit
    local function after_file_write(path, content)
        if path and path:match("autoload%.md$") then
            table.insert(_pending_check, path)
        end
    end

    -- Check autoload.md size after tool results added to message history
    local function after_tool_results(tool_results)
        while #_pending_check > 0 do
            local filepath = table.remove(_pending_check, 1)
            local f = io.open(filepath, "r")
            if f then
                local content = f:read("*all")
                f:close()
                if content and #content > MAX_AUTOLOAD_BYTES then
                    local msg = string.format(
                        "CRITICAL: `%s` is %d bytes, exceeding the %d byte limit. " ..
                        "Your persistent memory from `autoload.md` is being TRUNCATED. " ..
                        "Fix this NOW: use `edit_file` to trim `autoload.md` " ..
                        "under %d bytes, or you will lose memory each session.",
                        filepath, #content, MAX_AUTOLOAD_BYTES, MAX_AUTOLOAD_BYTES
                    )
                    log.warn("[memory] " .. msg)
                    if _app and _app.message_history then
                        _app.message_history:add_user_message(msg)
                    end
                end
            end
        end
    end

    -- Register hooks
    ctx:register_hook("after_file_write", after_file_write)
    ctx:register_hook("after_tool_results", after_tool_results)

    -- Hook: inject autoload.md into system prompt (with instructions)
    ctx:register_hook("before_system_prompt", function(prompt)
        local autoload = get_autoload()
        if autoload then
            return prompt .. (
                "\n\n## Persistent Memory\n" ..
                "You have a persistent memory directory at `.aicoder/memory/`.\n" ..
                "You manage it yourself using `write_file`/`edit_file`.\n" ..
                "- `autoload.md` < 2KB: This file (loaded into your prompt each session).\n" ..
                "- `index.md`: Your main working file. Organize project knowledge, user preferences, patterns.\n" ..
                "- Create more `.md` files for different topics.\n\n" ..
                "### Current Memory\n" ..
                autoload
            )
        end
        return prompt
    end)

    -- Register /memory command (alias /m)
    ctx:register_command("memory", function(args)
        local parts = {}
        for p in args:gmatch("%S+") do table.insert(parts, p) end
        local subcmd = parts[1] or ""

        if subcmd == "init" then
            -- Check if already initialized
            local f = io.open(MEMORY_DIR .. "/.", "r")
            if f then
                f:close()
                log.info("[memory] already initialized")
                return
            end

            -- Create memory directory
            os.execute("mkdir -p " .. MEMORY_DIR)

            -- Create index.md with instructions for the AI
            local index_content = (
                "# Memory Index\n\n" ..
                "This directory is your persistent memory. The AI manages these files using write_file/edit_file.\n\n" ..
                "## Rules\n" ..
                "- `autoload.md` (max 2KB) is loaded into your system prompt each session. Keep it concise.\n" ..
                "- `index.md` is your working memory. Organize project knowledge, patterns, conventions here.\n" ..
                "- Create additional `.md` files for specific topics as needed.\n" ..
                "- Update memory when you learn something important about the project or user preferences.\n\n" ..
                "## Guidelines\n" ..
                "- Be specific. Prefer facts over vague statements.\n" ..
                "- Replace \"today\", \"yesterday\", \"last time\" with actual dates.\n" ..
                "- Prune stale entries. Don't let contradictions accumulate.\n"
            )
            local f = io.open(INDEX_FILE, "w")
            if f then
                f:write(index_content)
                f:close()
            end

            -- Create autoload.md only if it doesn't exist
            local f2 = io.open(AUTOLOAD_FILE, "r")
            if not f2 then
                f2 = io.open(AUTOLOAD_FILE, "w")
                if f2 then
                    f2:write("_No persistent memories yet._")
                    f2:close()
                end
            else
                f2:close()
            end

            log.success("[memory] Memory initialized at " .. MEMORY_DIR)

            -- Tell the AI via a user message (some APIs reject multiple system messages)
            if ctx.app and ctx.app.message_history then
                ctx.app.message_history:add_user_message(
                    "## Memory System\n\n" ..
                    "`.aicoder/memory/` persistent memory has been initialized.\n" ..
                    "- `autoload.md` (max 2KB): loaded into your system prompt each session.\n" ..
                    "- `index.md`: working memory file. Update with key learnings.\n" ..
                    "- Create additional `.md` files as needed.\n" ..
                    "Use `write_file`/`edit_file` to manage memory files."
                )
            end

        elseif subcmd == "rm-all" then
            local f = io.open(MEMORY_DIR .. "/.", "r")
            if not f then
                log.info("[memory] not initialized")
                return
            end
            f:close()

            io.write("Remove all memory files? [y/N]: ")
            local answer = io.read("*line")
            if answer and answer:match("^%s*[yY]") then
                os.execute("rm -rf " .. MEMORY_DIR)
                log.success("[memory] " .. MEMORY_DIR .. " removed")
            else
                log.info("[memory] cancelled")
            end

        elseif subcmd == "status" then
            local c = config.colors
            local lines = {}
            table.insert(lines, c.bold .. "Memory Status:" .. c.reset)

            -- Check if memory dir exists
            local f = io.open(MEMORY_DIR .. "/.", "r")
            local exists = f ~= nil
            if f then f:close() end

            if not exists then
                table.insert(lines, "  Not initialized. Run " .. c.green .. "/memory init" .. c.reset)
                print(table.concat(lines, "\n"))
                return
            end

            -- autoload.md (check active, then disabled)
            local f = io.open(AUTOLOAD_FILE, "r")
            if f then
                local content = f:read("*all")
                f:close()
                local size = #content
                local ok = size <= MAX_AUTOLOAD_BYTES
                table.insert(lines, "  " .. c.cyan .. "autoload.md" .. c.reset ..
                    " (" .. size .. " bytes" .. (ok and "" or c.red .. " OVER LIMIT" .. c.reset) .. ")" ..
                    (ok and " [injected]" or ""))
            else
                local f2 = io.open(AUTOLOAD_DISABLED, "r")
                if f2 then
                    local content = f2:read("*all")
                    f2:close()
                    table.insert(lines, "  " .. c.cyan .. "autoload.md.disabled" .. c.reset ..
                        " (" .. #content .. " bytes) [disabled]")
                else
                    table.insert(lines, "  " .. c.cyan .. "autoload.md" .. c.reset .. " (not found)")
                end
            end

            -- index.md
            local f = io.open(INDEX_FILE, "r")
            if f then
                local content = f:read("*all")
                f:close()
                table.insert(lines, "  " .. c.cyan .. "index.md" .. c.reset ..
                    " (" .. #content .. " bytes)")
            else
                table.insert(lines, "  " .. c.cyan .. "index.md" .. c.reset .. " (not found)")
            end

            -- Count additional .md files
            local extra = 0
            local handle = io.popen(
                "ls " .. MEMORY_DIR .. "/*.md 2>/dev/null | grep -v 'autoload.md$' | grep -v 'index.md$' | wc -l"
            )
            if handle then
                extra = tonumber(handle:read("*all")) or 0
                handle:close()
            end
            if extra > 0 then
                table.insert(lines, "  + " .. extra .. " additional file(s)")
            end

            print(table.concat(lines, "\n"))

        elseif subcmd == "on" then
            local f = io.open(AUTOLOAD_DISABLED, "r")
            if f then
                f:close()
                os.rename(AUTOLOAD_DISABLED, AUTOLOAD_FILE)
                log.success("[memory] enabled (restored autoload.md)")
            else
                local f2 = io.open(AUTOLOAD_FILE, "r")
                if f2 then
                    f2:close()
                    log.info("[memory] already enabled")
                else
                    log.info("[memory] not initialized, use /memory init")
                end
            end

        elseif subcmd == "off" then
            local f = io.open(AUTOLOAD_FILE, "r")
            if f then
                f:close()
                os.rename(AUTOLOAD_FILE, AUTOLOAD_DISABLED)
                log.info("[memory] disabled (autoload.md → autoload.md.disabled)")
            else
                local f2 = io.open(AUTOLOAD_DISABLED, "r")
                if f2 then
                    f2:close()
                    log.info("[memory] already disabled")
                else
                    log.info("[memory] not initialized, use /memory init")
                end
            end

        else
            local c = config.colors
            print(c.bold .. "Usage:" .. c.reset)
            print("  " .. c.green .. "/memory " .. c.reset .. "rm-all  Remove all memory files (safe prompt)")
            print("  " .. c.green .. "/memory init" .. c.reset .. "   Create .aicoder/memory/ structure")
            print("  " .. c.green .. "/memory status" .. c.reset .. " Show memory file info")
            print("  " .. c.green .. "/memory on" .. c.reset .. "   Enable autoload injection")
            print("  " .. c.green .. "/memory off" .. c.reset .. "  Disable autoload injection")
            print("  " .. c.green .. "/m" .. c.reset .. "           Alias for /memory")
        end
    end, "Persistent memory management. Usage: /memory init|status|on|off", {"m"})

    return {name = "memory"}
end

return M
