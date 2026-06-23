-- Snippets Plugin - Reusable prompt snippets
-- Ported from Python snippets.py

-- Features:
-- - Load snippets from .aicoder/snippets (project) and ~/.config/luna/snippets (global)
-- - Local snippets override global on name collision
-- - Tab completion with @@ prefix
-- - Automatic snippet replacement in prompts
-- - /snippets command to list available snippets

local M = {}

local log = require("utils.log")

function M.create_plugin(self, ctx)
    local home_dir = os.getenv("HOME") or "/tmp"
    local project_snippets_dir = ".aicoder/snippets"
    local global_snippets_dir = home_dir .. "/.config/luna/snippets"

    -- Cache for snippet files: {filename: (source, dir_path)}
    local _cache = {
        snippets = {},   -- filename -> (source, dir_path)
        mtimes = {},     -- dir_path -> mtime
    }

    local function _dir_exists(path)
        local f = io.open(path, "r")
        if f then
            f:close()
            return true
        end
        return false
    end

    local function _get_dirs()
        -- Get snippet directories in scan order (global first, local second for override)
        local dirs = {}
        if _dir_exists(global_snippets_dir) then
            table.insert(dirs, {source = "global", dir = global_snippets_dir})
        end
        if _dir_exists(project_snippets_dir) then
            table.insert(dirs, {source = "local", dir = project_snippets_dir})
        end
        return dirs
    end

    local function _refresh_cache()
        -- Refresh snippet cache if any directory mtime changed
        local dirs = _get_dirs()
        if #dirs == 0 then
            return
        end

        local need_reload = false
        for _, d in ipairs(dirs) do
            local ok, mtime = pcall(function()
                local f = io.open(d.dir, "r")
                if not f then return nil end
                f:close()
                -- Use lfs if available for proper mtime, else just mark as needing reload
                return 1
            end)
            if ok and mtime then
                if _cache.mtimes[d.dir] ~= mtime then
                    need_reload = true
                    break
                end
            else
                -- Can't check mtime, force reload
                need_reload = true
                break
            end
        end

        if not need_reload and next(_cache.snippets) then
            return
        end

        -- Reload from all dirs (global first, local overrides)
        _cache.snippets = {}
        for _, d in ipairs(dirs) do
            local ok = pcall(function()
                -- Try to use luafilesystem if available
                local lfs = require("lfs")
                local attr = lfs.attributes(d.dir)
                if attr then
                    _cache.mtimes[d.dir] = attr.modification
                end
                
                for file in lfs.dir(d.dir) do
                    if not file:match("^%.") then
                        _cache.snippets[file] = {source = d.source, dir = d.dir}
                    end
                end
            end)
            
            if not ok then
                -- Fallback: simple directory listing without mtime
                _cache.mtimes[d.dir] = 1
                local handle = io.popen('ls -1 "' .. d.dir .. '" 2>/dev/null || true')
                if handle then
                    for file in handle:lines() do
                        if not file:match("^%.") then
                            _cache.snippets[file] = {source = d.source, dir = d.dir}
                        end
                    end
                    handle:close()
                end
            end
        end
    end

    local function _get_snippets()
        _refresh_cache()
        local result = {}
        for name, _ in pairs(_cache.snippets) do
            table.insert(result, name)
        end
        table.sort(result)
        return result
    end

    local function _load_snippet(name)
        -- Load snippet content by name (with or without extension)
        _refresh_cache()

        -- Try exact match first
        if _cache.snippets[name] then
            local data = _cache.snippets[name]
            local path = data.dir .. "/" .. name
            local f = io.open(path, "r")
            if f then
                local content = f:read("*all")
                f:close()
                return content
            end
        end

        -- Try without extension (find first matching file)
        local name_without_ext = name:match("(.+)%.") or name
        for filename, data in pairs(_cache.snippets) do
            local stem = filename:match("(.+)%.") or filename
            if stem == name_without_ext then
                local path = data.dir .. "/" .. filename
                local f = io.open(path, "r")
                if f then
                    local content = f:read("*all")
                    f:close()
                    return content
                end
            end
        end

        return nil
    end

    -- ==================== Tab Completion ====================
    
    -- Separate table to store matches across completer calls
    local _completion_state = {
        matches = {}
    }
    
    local function snippet_completer(text, state)
        -- Only activate for @@ prefix
        if not text:match("^@@") then
            return nil
        end
        
        -- Strip @@ prefix for matching
        local prefix = text:match("^@@(.+)") or ""
        
        if state == 0 then
            _completion_state.matches = {}
            local snippets = _get_snippets()
            
            -- Match snippets (case-insensitive)
            for _, snippet in ipairs(snippets) do
                if prefix == "" or snippet:sub(1, #prefix):lower() == prefix:lower() then
                    -- Return name WITHOUT @@ prefix so readline completes correctly
                    table.insert(_completion_state.matches, snippet)
                end
            end
        end
        
        -- Return the appropriate match based on state
        if state < #_completion_state.matches then
            return _completion_state.matches[state + 1]
        end
        return nil
    end

    -- Register completer
    ctx:register_completer(snippet_completer)

    -- ==================== Hook for Snippet Replacement ====================

    local function transform_prompt_with_snippets(prompt)
        -- Transform prompt by replacing @@snippet with file content
        -- Hook: after_user_prompt
        
        if not prompt or not prompt:match("@@") then
            return prompt
        end

        -- Find all @@snippet references
        local matches = {}
        for snippet_name in prompt:gmatch("@@(%S+)") do
            table.insert(matches, snippet_name)
        end

        for _, snippet_name in ipairs(matches) do
            local content = _load_snippet(snippet_name)
            if content then
                -- Replace @@snippet with content (need to escape pattern magic chars . and -)
                local escaped_name = snippet_name:gsub("[%.%-]", "%%%1")
                local pattern = "@@" .. escaped_name
                prompt = prompt:gsub(pattern, content)
                -- Log the replacement
                log.success("Loaded snippet: @@" .. snippet_name)
            else
                -- Warn user about missing snippet
                log.warn("Snippet '@@" .. snippet_name .. "' not found")
            end
        end

        return prompt
    end

    -- Register hook
    ctx:register_hook("after_user_prompt", transform_prompt_with_snippets)

    -- ==================== /snippets Command ====================

    local function handle_snippets_command(args)
        -- Handle /snippets command - list available snippets
        local dirs = _get_dirs()
        if #dirs == 0 then
            log.warn("No snippets directory found.")
            log.dim("  Create .aicoder/snippets/ (project) or ~/.config/luna/snippets/ (global)")
            return
        end

        local snippets = _get_snippets()
        if #snippets == 0 then
            log.warn("No snippets found.")
            return
        end

        -- Display snippets grouped by source
        local dirs_display = {}
        for _, d in ipairs(dirs) do
            table.insert(dirs_display, d.source == "local" and "project" or "global")
        end
        log.info("Available snippets (" .. table.concat(dirs_display, " + ") .. "):")

        for _, snippet in ipairs(snippets) do
            local data = _cache.snippets[snippet]
            local tag = data.source == "local" and "local" or "global"
            log.print("  - " .. snippet .. " [" .. tag .. "]")
        end

        -- Show usage
        log.dim("\nUsage: Include @@snippet_name in your prompt.")
        log.dim("Example: Use @@ultrathink to analyze the code")
    end

    -- Register command
    ctx:register_command("snippets", handle_snippets_command, "List available snippets")

    -- No cleanup needed
    return nil
end

return M