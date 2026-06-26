-- Plugin: memory
-- Auto-managed persistent memory for cross-session learning.
--
-- Creates .aicoder/memory/ structure:
--   autoload.md - auto-injected into system prompt (limit via AICODER_MEMORY_AUTOLOAD_LIMIT)
--   index.md - main memory file, AI manages freely
--   *.md - any additional files AI creates
--
-- To disable: PLUGINS_DENY=...,memory (env var at startup)
-- /memory status - show memory state
-- /memory rm-all - remove all memory files

local config = require("core.config")
local log = require("utils.log")

local MEMORY_DIR = ".aicoder/memory"
local AUTOLOAD_FILE = MEMORY_DIR .. "/autoload.md"
local INDEX_FILE = MEMORY_DIR .. "/index.md"
local MAX_AUTOLOAD_BYTES = tonumber(os.getenv("AICODER_MEMORY_AUTOLOAD_LIMIT")) or 2048

local _pending_check = {}
local _app = nil

local M = {}

-- Auto-init memory dir + seed files if missing
local function _auto_init()
    local f = io.open(MEMORY_DIR .. "/.", "r")
    if f then f:close() return true end

    os.execute("mkdir -p " .. MEMORY_DIR)
    local index_content = (
        "# Memory Index\n\n" ..
        "This directory is your persistent memory. Manage files via write_file/edit_file.\n\n" ..
        "## Rules\n" ..
        "- `autoload.md` (< 2KB) - critical facts loaded into every session prompt.\n" ..
        "- `index.md` - working memory for project knowledge, patterns, conventions.\n" ..
        "- Create more `.md` files for specific topics as needed.\n" ..
        "- Update memory when you learn something important.\n\n" ..
        "## Guidelines\n" ..
        "- Be specific. Prefer facts over vague statements.\n" ..
        "- Replace dates with actual values (no 'today', 'yesterday').\n" ..
        "- Prune stale entries.\n"
    )
    local fw = io.open(INDEX_FILE, "w")
    if fw then fw:write(index_content) fw:close() end

    local fw2 = io.open(AUTOLOAD_FILE, "w")
    if fw2 then fw2:write("_No persistent memories yet._") fw2:close() end

    log.info("[memory] auto-initialized at " .. MEMORY_DIR)
    return true
end

-- Read autoload.md content (nil if missing or empty)
local function _get_autoload()
    local f = io.open(AUTOLOAD_FILE, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    if not content or #content == 0 then return nil end
    if #content > MAX_AUTOLOAD_BYTES then
        log.warn("[memory] autoload.md truncated (" .. #content .. " bytes, max " .. MAX_AUTOLOAD_BYTES .. ")")
        local trunc_note = "\n\n[... truncated to " .. MAX_AUTOLOAD_BYTES .. " bytes ...]"
        content = content:sub(1, MAX_AUTOLOAD_BYTES - #trunc_note) .. trunc_note
    end
    return content
end

-- List .md files in memory dir
local function _list_memory_files()
    local files = {}
    local f = io.popen("ls " .. MEMORY_DIR .. "/*.md 2>/dev/null")
    if f then
        for line in f:lines() do
            local name = line:match("([^/]+)%.md$")
            if name then table.insert(files, name .. ".md") end
        end
        f:close()
    end
    return files
end

-- Build the memory section for system prompt
local function _build_memory_section()
    _auto_init()

    local autoload = _get_autoload()
    local files = _list_memory_files()
    local has_files = #files > 0

    local section = "\n\n## Persistent Memory"
    section = section .. "\nMemory files live in `.aicoder/memory/` (relative to CWD, already exists)."
    section = section .. "\nManage them with `write_file`/`edit_file`. Keep everything inside that directory."
    section = section .. "\n"
    section = section .. "\n**How it works:**"
    section = section .. "\n- `autoload.md` (< " .. MAX_AUTOLOAD_BYTES .. " bytes) - loaded into **every session's prompt**. Put critical facts here."
    section = section .. "\n- `index.md` - main working memory (project knowledge, patterns, user preferences)."
    section = section .. "\n- Create additional `.md` files for specific topics."

    if has_files then
        section = section .. "\n\n### Memory Files"
        for _, name in ipairs(files) do
            section = section .. "\n- " .. name
        end
    end

    if autoload then
        section = section .. "\n\n### autoload.md\n" .. autoload
    end

    return section
end

-- Rebuild system prompt in-place
local function _rebuild_system_prompt()
    if not (_app and _app.message_history) then return end
    local PB = require("core.prompt_builder")
    local system_prompt = PB.PromptBuilder.build_system_prompt()
    if _app.plugin_system then
        system_prompt = _app.plugin_system:call_hooks_with_return("before_system_prompt", system_prompt)
    end
    local messages = _app.message_history:get_messages()
    if #messages > 0 and messages[1].role == "system" then
        messages[1].content = system_prompt
        log.info("[memory] system prompt refreshed")
    end
end

function M:create_plugin(ctx)
    _app = ctx.app

    -- Queue autoload.md for size check after write/edit
    local function after_file_write(path, content)
        if path and path:match("autoload%.md$") then
            table.insert(_pending_check, path)
        end
    end

    -- Check autoload.md size after tool results
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

    ctx:register_hook("after_file_write", after_file_write)
    ctx:register_hook("after_tool_results", after_tool_results)

    -- Inject memory section into system prompt
    ctx:register_hook("before_system_prompt", function(prompt)
        return prompt .. _build_memory_section()
    end)

    -- Refresh prompt after compaction
    ctx:register_hook("after_compaction", _rebuild_system_prompt)

    -- /memory command
    ctx:register_command("memory", function(args)
        local parts = {}
        for p in args:gmatch("%S+") do table.insert(parts, p) end
        local subcmd = parts[1] or ""

        if subcmd == "rm-all" then
            io.write("Remove all memory files? [y/N]: ")
            local answer = io.read("*line")
            if answer and answer:match("^%s*[yY]") then
                os.execute("rm -rf " .. MEMORY_DIR)
                _rebuild_system_prompt()
                log.success("[memory] " .. MEMORY_DIR .. " reset")
            else
                log.info("[memory] cancelled")
            end

        else  -- status (default)
            local c = config.colors
            local lines = {}
            table.insert(lines, c.bold .. "Memory Status:" .. c.reset)
            table.insert(lines, "  Disable via " .. c.cyan .. "PLUGINS_DENY=...,memory" .. c.reset)

            local f = io.open(MEMORY_DIR .. "/.", "r")
            if not f then
                table.insert(lines, "  Not initialized.")
                print(table.concat(lines, "\n"))
                return
            end
            f:close()

            -- autoload.md
            local f = io.open(AUTOLOAD_FILE, "r")
            if f then
                local content = f:read("*all")
                f:close()
                local size = #content
                local ok = size <= MAX_AUTOLOAD_BYTES
                table.insert(lines, "  " .. c.cyan .. "autoload.md" .. c.reset ..
                    " (" .. size .. " bytes" .. (ok and "" or c.red .. " OVER LIMIT" .. c.reset) .. ")")
            end

            -- index.md
            local f = io.open(INDEX_FILE, "r")
            if f then
                local content = f:read("*all")
                f:close()
                table.insert(lines, "  " .. c.cyan .. "index.md" .. c.reset ..
                    " (" .. #content .. " bytes)")
            end

            -- other .md files
            local handle = io.popen(
                "ls " .. MEMORY_DIR .. "/*.md 2>/dev/null | grep -v 'autoload.md$' | grep -v 'index.md$'"
            )
            if handle then
                for fname in handle:lines() do
                    local short = fname:match("/([^/]+)$")
                    local f = io.open(fname, "r")
                    if f then
                        local content = f:read("*all")
                        f:close()
                        table.insert(lines, "  " .. c.cyan .. short .. c.reset ..
                            " (" .. #content .. " bytes)")
                    end
                end
                handle:close()
            end

            print(table.concat(lines, "\n"))
        end
    end)
end

return M
