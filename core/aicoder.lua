-- AICoder - Main Application Class
-- Ported from Python aicoder.py

local config = require("core.config")
local Stats = require("core.stats")
local MessageHistory = require("core.message_history")
local ToolManager = require("core.tool_manager")
local stdin_utils = require("utils.stdin_utils")
local file_utils = require("utils.file_utils")

-- Provider selection based on API_FORMAT or endpoint detection
local function select_api_client()
    local format = os.getenv("API_FORMAT") or ""
    local endpoint = os.getenv("API_ENDPOINT") or ""
    
    if format == "openai" or format == "pollinations" then
        return require("core.openai_client")
    elseif format == "anthropic" then
        return require("core.anthropic_client")
    end
    
    -- Auto-detect from endpoint URL
    if endpoint:find("anthropic") or endpoint:find("claude") then
        return require("core.anthropic_client")
    end
    
    -- Default to OpenAI-compatible (api_client)
    return require("core.openai_client")
end
local ApiClient = select_api_client()

local InputHandler = require("core.input_handler")
local ContextBar = require("core.context_bar")
local CompactionService = require("core.compaction_service")
local CommandHandler = require("core.command_handler")
local ToolExecutor = require("core.tool_executor")
local SessionManager = require("core.session_manager")
local PluginSystem = require("core.plugin_system")
local log = require("utils.log")

local AICoder = {}
AICoder.__index = AICoder

function AICoder.new()
    local self = setmetatable({}, AICoder)
    
    -- State
    self.is_running = true
    self.is_processing = false
    self.next_prompt = nil
    
    -- Core components
    self.stats = Stats.new()
    self.message_history = MessageHistory.new(self.stats)
    self.tool_manager = ToolManager.new(self.stats)
    self.api_client = ApiClient.new(self.stats, self.tool_manager, self.message_history)
    self.plugin_system = PluginSystem.new(".aicoder/plugins")
    self.context_bar = ContextBar.new(self.plugin_system)
    self.input_handler = InputHandler.new(self.context_bar, self.stats, self.message_history)
    self.compaction_service = CompactionService.new(self.api_client)
    
    -- Extracted components
    self.tool_executor = ToolExecutor.new(self.tool_manager, self.message_history, self.plugin_system)
    self.session_manager = SessionManager.new(self)
    
    -- Command system
    self.command_handler = CommandHandler.new(
        self.message_history,
        self.input_handler,
        self.stats,
        self.plugin_system
    )
    
    -- Hooks
    self.notify_hooks = nil
    
    -- Detect pipe mode
    self._is_pipe_mode = stdin_utils.is_stdin_piped()
    
    -- Auto-save functionality
    local auto_save_env = os.getenv("AICODER_AUTO_SAVE")
    self._auto_save_enabled = (auto_save_env ~= "0" and auto_save_env ~= "false" and auto_save_env ~= "no")
    local default_path = ".aicoder/last-session.json"
    local env_path = os.getenv("AICODER_AUTO_SAVE_FILE")
    self._session_file_path = env_path or default_path
    self._using_default_save_path = (env_path == nil)
    
    return self
end

function AICoder:set_next_prompt(prompt)
    self.next_prompt = prompt
end

function AICoder:get_next_prompt()
    local prompt = self.next_prompt
    self.next_prompt = nil
    return prompt
end

function AICoder:has_next_prompt()
    return self.next_prompt ~= nil
end

function AICoder:initialize()
    config.validate_config()
    self:initialize_system_prompt()
    
    -- Create isolated temp directory for this instance
    self:_create_tmp_dir()
    
    -- Set API client on message history
    self.message_history:set_api_client(self.api_client)
    
    -- Set plugin system on components
    self.plugin_system:set_app(self)
    self.tool_manager:set_plugin_system(self.plugin_system)
    self.message_history:set_plugin_system(self.plugin_system)
    self.api_client:set_plugin_system(self.plugin_system)
    
    -- Load plugins
    self.plugin_system:load_plugins()
    
    -- Transfer plugin completers to input_handler
    local plugin_completers = self.plugin_system:get_completers()
    for _, completer in ipairs(plugin_completers) do
        self.input_handler:register_completer(completer)
    end
    
    -- Register plugin tools
    local plugin_tools = self.plugin_system:get_plugin_tools()
    for tool_name, tool_data in pairs(plugin_tools) do
        local tool_def = {
            type = "plugin",
            description = tool_data.description,
            parameters = tool_data.parameters,
            auto_approved = tool_data.auto_approved or false,
            execute = tool_data.execute,
        }
        if tool_data.formatArguments then
            tool_def.formatArguments = tool_data.formatArguments
        end
        if tool_data.generatePreview then
            tool_def.generatePreview = tool_data.generatePreview
        end
        self.tool_manager.tools[tool_name] = tool_def
    end
    
    -- Register plugin commands
    local plugin_commands = self.plugin_system:get_plugin_commands()
    for cmd_name, cmd_data in pairs(plugin_commands) do
        self.command_handler:register_simple_command(
            cmd_name, cmd_data.fn, cmd_data.description
        )
    end
end

function AICoder:initialize_system_prompt()
    local PB = require("core.prompt_builder")
    local system_prompt = PB.PromptBuilder.build_system_prompt()
    self.message_history:add_system_message(system_prompt)
end

function AICoder:run()
    -- Check if non-interactive (piped input)
    if not stdin_utils.is_stdin_tty() then
        self:run_non_interactive()
        return
    end
    
    log.success("Luna initialized")
    
    -- Print configuration info (like v3)
    self.config = require("core.config")
    self.config.print_startup_info()
    
    log.success("Type your message or /help for commands.")
    
    while self.is_running do
        -- Get user input
        if self.plugin_system then
            self.plugin_system:call_hooks("before_user_prompt")
        end
        
        local user_input
        if self:has_next_prompt() then
            user_input = self:get_next_prompt()
        else
            user_input = self.input_handler:get_user_input()
        end
        
        if not user_input or user_input == "" then
            goto continue
        end
        
        user_input = user_input:gsub("^%s+", ""):gsub("%s+$", "")
        
        -- Apply plugin transformations (Python: user_input = hook(...) or user_input)
        local transformed = self.plugin_system:call_hooks_with_return("after_user_prompt", user_input)
        if transformed ~= nil then user_input = transformed end
        
        -- Handle commands
        if user_input:sub(1, 1) == "/" then
            local result = self.command_handler:handle_command(user_input)
            if result.should_quit then
                self.is_running = false
                break
            end
            if not result.run_api_call then
                goto continue
            end
            if result.message then
                self:add_user_input(result.message)
            end
        else
            self:add_user_input(user_input)
        end
        
        -- Process with AI (session_manager handles printing)
        self.session_manager:process_with_ai()

        ::continue::
    end
    
    self:shutdown()
end

function AICoder:add_user_input(user_input)
    local final_input = user_input:match("^%s*(.-)%s*$")
    self.message_history:add_user_message(final_input)
    self.stats:increment_user_interactions()
end

function AICoder:shutdown()
    -- Clean up temp directory
    self:_cleanup_tmp_dir()
    
    -- Auto-save on exit (like v3)
    if self._auto_save_enabled then
        self:save_session()
    end
    
    -- Clean shutdown
    if self.input_handler and self.input_handler.close then
        self.input_handler:close()
    end
    if not self._is_pipe_mode then
        log.success("Shutting down...")
    end
end

function AICoder:_create_tmp_dir()
    -- Create isolated temp directory for this instance
    local temp_utils = require("utils.temp_file_utils")
    local tmp_base = temp_utils.get_temp_dir()
    local id = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
    local tmp_dir = tmp_base .. "/luna-" .. id
    
    file_utils.mkdir_p(tmp_dir)
    config.set_tmp_dir(tmp_dir)
    if config.debug() then
        log.debug("Temp dir: " .. tmp_dir)
    end
end

function AICoder:_cleanup_tmp_dir()
    local tmp_dir = config.get_tmp_dir()
    if tmp_dir and tmp_dir:match("luna%-") then
        -- Safety check: only remove if it's a luna temp dir
        os.execute("rm -rf " .. tmp_dir)
    end
end

function AICoder:save_session()
    -- Save current session to file
    local ok, err = pcall(function()
        local save_cmd = require("core.commands.save")
        local context = {
            message_history = self.message_history,
        }
        local cmd = save_cmd.SaveCommand.new(context)
        -- Extract filename from path
        local filename = self._session_file_path
        cmd:execute({filename})
    end)
    
    if not ok then
        -- Don't let save errors crash shutdown
        if config.debug() then
            log.debug("Session save failed: " .. tostring(err))
        end
    end
end

-- Calculate tool definition tokens once at startup
function AICoder:_calculate_tool_tokens()
    local tools = self.tool_manager:get_tool_definitions()
    if tools and #tools > 0 then
        local token_estimator = require("core.token_estimator")
        local json = require("utils.json")
        local tools_json = json.encode(tools)
        local tokens = token_estimator._estimate_weighted_tokens(tools_json)
        token_estimator.set_tools_tokens(tokens)
        if config.debug() then
            log.debug("Tool tokens estimated: " .. tostring(tokens))
        end
    end
end

-- Run in non-interactive mode (piped input)
function AICoder:run_non_interactive()
    if config.debug() then
        log.debug("*** run_non_interactive called")
    end

    -- Auto-enable YOLO mode since no tty for approval prompts
    config.set_yolo_mode(true)

    local stdin_utils = require("utils.stdin_utils")
    local user_input = stdin_utils.read_stdin_as_string()
    if not user_input or user_input == "" then
        if config.debug() then log.debug("*** no stdin input, returning") end
        return
    end

    for line in user_input:gmatch("[^\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line == "" then
            goto continue
        end

        -- Apply plugin transformations (like vision @image processing)
        local transformed = self.plugin_system:call_hooks_with_return("after_user_prompt", line)
        if transformed == nil or transformed == "" then
            goto continue  -- Plugin handled it or empty
        end
        
        -- Handle command
        if transformed:sub(1, 1) == "/" then
            local result = self.command_handler:handle_command(transformed)
            if result.should_quit then
                self:shutdown()
                return
            end
            if not result.run_api_call then
                goto continue
            end
            if result.message then
                self:add_user_input(result.message)
            end
        else
            self:add_user_input(transformed)
        end

        ::continue::
    end

    -- Process with AI
    if #self.message_history.messages > 1 then  -- system msg + user msgs
        self.session_manager:process_with_ai()
    end
    
    self:shutdown()
end

-- Run in socket-only mode (no readline, only socket commands)
function AICoder:run_socket_only()
    if config.debug() then
        log.debug("*** run_socket_only called")
    end

    -- Auto-enable YOLO mode since approval system won't work without readline
    config.set_yolo_mode(true)
    log.success("YOLO mode auto-enabled (socket-only mode)")

    log.success("Socket-only mode. Use socket commands to control AI Coder.")

    self.is_running = true
    while self.is_running do
        if self.socket_server and self.socket_server.poll then
            self.socket_server:poll()
        end
        os.execute("sleep 1")
    end
end

-- Add a message from plugins to conversation
function AICoder:add_plugin_message(message)
    self.message_history:add_user_message(message)
    if self.stats then
        self.stats:increment_user_interactions()
    end
end

-- Handle test message injection for testing
function AICoder:handle_test_message(message)
    local assistant_message = {
        role = "assistant",
        content = message.content or "",
        tool_calls = message.tool_calls or {},
    }
    self.message_history:add_assistant_message(assistant_message)

    if not assistant_message.tool_calls or type(assistant_message.tool_calls) ~= "table" or #assistant_message.tool_calls == 0 then
        return {}
    end

    -- Execute tool calls
    return self.tool_executor:execute_tool_calls(assistant_message.tool_calls)
end

-- Perform auto-compaction (delegates to session_manager)
function AICoder:perform_auto_compaction()
    if self.session_manager and self.session_manager._perform_auto_compaction then
        self.session_manager:_perform_auto_compaction()
    end
end

-- Call notification hook
function AICoder:call_notify_hook(hook_name)
    if self.notify_hooks and self.notify_hooks[hook_name] then
        local ok, err = pcall(self.notify_hooks[hook_name])
        if not ok and config.debug() then
            log.warn("[!] Hook " .. hook_name .. " failed: " .. tostring(err))
        end
    end
end

-- Centralized method to save the current session
function AICoder:save_session(force)
    force = force or false
    if self._is_pipe_mode and self._using_default_save_path and not force then
        return false
    end
    local path = self._session_file_path or "./.aicoder/sessions/last-session.json"
    local ok, err = pcall(function()
        if self.command_handler and self.command_handler.handle_command then
            self.command_handler:handle_command("/save " .. path)
        end
    end)
    if not ok then return false end
    return true
end

-- Register auto-save (best-effort: we hook into shutdown instead of atexit)
function AICoder:register_auto_save()
    self._auto_save_enabled = true
end

-- Auto-save on exit
function AICoder:_auto_save_on_exit()
    self:save_session()
end

-- Setup signal handlers
function AICoder:_setup_signal_handlers()
    -- Best-effort: defer to input_handler if it has setup_signal_handlers
    if self.input_handler and self.input_handler.setup_signal_handlers then
        self.input_handler:setup_signal_handlers()
    end
end

return AICoder