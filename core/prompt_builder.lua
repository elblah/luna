-- Universal prompt builder system
-- Ported from Python core/prompt_builder.py

local M = {}

local PromptContext = {}
PromptContext.__index = PromptContext

function PromptContext.new()
    local self = setmetatable({}, PromptContext)
    self.current_directory = os.getenv("PWD") or os.getenv("CWD") or "."
    self.current_datetime = os.date("!%Y-%m-%d", os.time())
    self.agents_content = nil
    return self
end

M.PromptContext = PromptContext

local PromptOptions = {}
PromptOptions.__index = PromptOptions

function PromptOptions.new()
    local self = setmetatable({}, PromptOptions)
    self.override_prompt = nil
    self.append_prompt = nil
    return self
end

M.PromptOptions = PromptOptions

local PromptBuilder = {}
PromptBuilder.__index = PromptBuilder
PromptBuilder._default_prompt_template = nil

function PromptBuilder.is_initialized()
    return PromptBuilder._default_prompt_template ~= nil
end

function PromptBuilder.initialize()
    -- Try package-relative path first
    local script_path = debug.getinfo and debug.getinfo(1, "S").source:gsub("@", "") or "."
    local package_dir = script_path:gsub("/[^/]+$", "")
    
    local template_paths = {
        package_dir .. "/../prompts/default-system-prompt.md",
        "./prompts/default-system-prompt.md",
        "prompts/default-system-prompt.md",
        "default-system-prompt.md",
    }

    for _, template_path in ipairs(template_paths) do
        local f = io.open(template_path, "r")
        if f then
            PromptBuilder._default_prompt_template = f:read("*all")
            f:close()
            return
        end
    end

    -- Use minimal fallback
    PromptBuilder._default_prompt_template = [[You are a helpful AI assistant.
You have access to various tools for file operations, search, and command execution.
Always follow user instructions carefully and provide helpful responses.]]
end

function PromptBuilder.build_prompt(context, options)
    options = options or PromptOptions.new()
    
    local prompt
    if options.override_prompt then
        prompt = options.override_prompt
    else
        if not PromptBuilder._default_prompt_template then
            PromptBuilder.initialize()
        end
        prompt = PromptBuilder._default_prompt_template
        
        -- Replace {variable} placeholders
        prompt = prompt:gsub("{([^}]+)}", function(var)
            if var == "current_directory" then
                return context.current_directory
            elseif var == "current_datetime" then
                return context.current_datetime
            elseif var == "agents_content" then
                return context.agents_content or ""
            else
                return "{" .. var .. "}"
            end
        end)
    end
    
    -- Append additional content from AICODER_SYSTEM_PROMPT_APPEND
    if options.append_prompt then
        prompt = prompt .. "\n\n" .. options.append_prompt
    end
    
    return prompt
end

-- Load AGENTS.md if it exists
function PromptBuilder.load_agents_content(context)
    local agents_paths = {
        context.current_directory .. "/AGENTS.md",
        "./AGENTS.md",
        "AGENTS.md",
    }

    for _, path in ipairs(agents_paths) do
        local f = io.open(path, "r")
        if f then
            context.agents_content = f:read("*all")
            f:close()
            return
        end
    end
end

-- Load PROMPT-OVERRIDE.md content if it exists
function PromptBuilder.load_prompt_override()
    local f = io.open("PROMPT-OVERRIDE.md", "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

-- Get basic available tools information
function PromptBuilder._get_available_tools_info()
    return [[Basic tools available: file operations (read, write, list),
search (grep), shell command execution, and more via API request.]]
end

-- Build the complete system prompt
function PromptBuilder.build_system_prompt()
    if not PromptBuilder._default_prompt_template then
        PromptBuilder.initialize()
    end

    local context = PromptContext.new()

    -- Load AGENTS.md
    local f = io.open("AGENTS.md", "r")
    if f then
        context.agents_content = f:read("*all")
        f:close()
    end

    -- Load prompt override: env var takes precedence
    local options = PromptOptions.new()
    local ok, config = pcall(require, "core.config")
    if ok and config and config.system_prompt then
        local env_prompt = config.system_prompt()
        if env_prompt and env_prompt ~= "" then
            options.override_prompt = env_prompt
        else
            local override = PromptBuilder.load_prompt_override()
            if override then
                options.override_prompt = override
            end
        end
        
        -- Append additional content from AICODER_SYSTEM_PROMPT_APPEND
        local append_content = config.system_prompt_append()
        if append_content and append_content ~= "" then
            options.append_prompt = append_content
        end
    end

    return PromptBuilder.build_prompt(context, options)
end

M.PromptBuilder = PromptBuilder

-- Module-level aliases for static methods (1-1 parity with Python classmethods)
M.is_initialized = PromptBuilder.is_initialized
M.initialize = PromptBuilder.initialize
M.build = PromptBuilder.build_prompt

return M
