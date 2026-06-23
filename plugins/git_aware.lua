-- Git Aware Plugin - Adds git context to AI system prompt
-- Detects if current directory is a git repo and adds awareness

local M = {}

local log = require("utils.log")
local config = require("core.config")

-- Cache git branch at module level - run once at plugin load
local _cached_git_branch = nil
local _cached_git_root = nil

function M._get_git_branch()
    local handle = io.popen("git branch --show-current 2>/dev/null")
    if not handle then return nil end
    local branch = handle:read("*all"):gsub("%s+", "")
    handle:close()
    if branch == "" then return nil end
    return branch
end

function M._get_git_root()
    local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
    if not handle then return nil end
    local root = handle:read("*all"):gsub("%s+", "")
    handle:close()
    if root == "" then return nil end
    return root
end

function M._is_repo_dirty()
    local handle = io.popen("git status --porcelain 2>/dev/null")
    if not handle then return false end
    local output = handle:read("*all")
    handle:close()
    return output and output ~= ""
end

function M.create_plugin(ctx)
    -- Run git commands once at load time
    _cached_git_branch = M._get_git_branch()
    _cached_git_root = M._get_git_root()

    if config.debug() then
        if _cached_git_branch then
            log.debug("[git_aware] Branch = '" .. _cached_git_branch .. "'")
        else
            log.debug("[git_aware] Not a git repository")
        end
    end

    -- Hook: Add git context to system prompt
    local function on_before_user_prompt()
        if not _cached_git_branch then return end

        local messages = ctx.app.message_history.messages
        if not messages or #messages == 0 then return end

        local system_msg = messages[1]
        if system_msg.role ~= "system" then return end

        local content = system_msg.content or ""
        if content:find("Git Repository:") then return end

        system_msg.content = content .. "\n\nGit Repository:\n- Branch: " .. _cached_git_branch .. "\n"
    end

    -- Hook: Add git status to context bar
    local function on_context_bar(current)
        if not _cached_git_branch then return current end

        local dirty = M._is_repo_dirty()
        local git_str
        if dirty then
            git_str = config.colors.yellow .. config.colors.bold .. "Git"
        else
            git_str = config.colors.dim .. "Git"
        end
        git_str = git_str .. config.colors.reset

        if current == "" then
            return git_str
        else
            return current .. " " .. git_str
        end
    end

    ctx:register_hook("before_user_prompt", on_before_user_prompt)
    ctx:register_hook("on_context_bar", on_context_bar)

    if config.debug() then
        log.debug("  - before_user_prompt hook (git awareness)")
        log.debug("  - on_context_bar hook (git status)")
    end

    return {}
end

return M.create_plugin
