-- Plugin System for Luna

local M = {}

-- Class-style aliases for 1-1 parity with Python
M.PluginSystem = M
M.PluginContext = M

local log = require("utils.log")
local config = require("core.config")
local datetime = require("utils.datetime_utils")
local BaseCommand = require("core.commands.base")

-- Plugin context for registration callbacks
local function create_plugin_context(self)
    return {
        app = nil,
        _register_tool_fn = function(name, fn, desc, params, auto_approved, format_args, generate_preview)
            self:_register_tool(name, fn, desc, params, auto_approved, format_args, generate_preview)
        end,
        _register_command_fn = function(name, handler, desc)
            self:_register_command(name, handler, desc)
        end,
        _register_hook_fn = function(event_name, handler)
            self:_register_hook(event_name, handler)
        end,
        _register_completer_fn = function(completer)
            self:_register_completer(completer)
        end,
        
        register_tool = function(ctx, name, fn, description, parameters, auto_approved, format_arguments, generate_preview)
            if ctx._register_tool_fn then
                ctx._register_tool_fn(name, fn, description, parameters, auto_approved, format_arguments, generate_preview)
            end
        end,
        
        register_command = function(ctx, name, handler, description)
            if ctx._register_command_fn then
                ctx._register_command_fn(name, handler, description)
            end
        end,
        
        register_hook = function(ctx, event_name, handler)
            if ctx._register_hook_fn then
                ctx._register_hook_fn(event_name, handler)
            end
        end,
        
        register_completer = function(ctx, completer)
            if ctx._register_completer_fn then
                ctx._register_completer_fn(completer)
            end
        end,
    }
end

local function new(plugins_dir, global_plugins_dir, bundled_plugins_dir)
    local home_dir = os.getenv("HOME") or "/home/blah"
    local script_dir = _G.SCRIPT_DIR or "."
    local self = {
        plugins_dir = plugins_dir or ".aicoder/plugins",
        global_plugins_dir = global_plugins_dir or home_dir .. "/.config/luna/plugins",
        bundled_plugins_dir = bundled_plugins_dir or script_dir .. "/plugins",
        plugins = {},
        loaded_plugin_names = {},  -- Track loaded plugin names to avoid duplicates
        tools = {},
        commands = {},
        hooks = {},
        cleanup_handlers = {},
        context = nil,
        _app = nil,
    }
    
    self.context = create_plugin_context(self)
    
    function self:set_app(app)
        self._app = app
        self.context.app = app
    end
    
    function self:_register_tool(name, fn, description, parameters, auto_approved, format_arguments, generate_preview)
        -- Filter by TOOLS_ALLOW (if set, only allowed tools register)
        local allowed = config.tools_allow()
        if allowed and not allowed[name] then
            return  -- Skip this tool - not in allowed list
        end
        
        -- Filter by TOOLS_DENY (deny wins)
        local denied = config.tools_deny()
        if denied[name] then
            return  -- Skip this tool - in deny list
        end
        
        local tool_def = {
            type = "function",
            description = description or "",
            auto_approved = auto_approved or false,
            parameters = parameters or {type = "object", properties = {}},
        }
        
        if fn then
            tool_def.execute = fn
        end
        if format_arguments then
            tool_def.formatArguments = format_arguments
        end
        if generate_preview then
            tool_def.generatePreview = generate_preview
        end
        
        self.tools[name] = tool_def
    end
    
    function self:_register_command(name, handler, description)
        local stored_name = name:gsub("^/", "")
        self.commands[name] = {
            get_name = function() return stored_name end,
            get_description = function() return description or "" end,
            get_aliases = function() return {} end,
            execute = function(_, args)
                local args_str
                if type(args) == "table" then
                    args_str = table.concat(args, " ")
                else
                    args_str = args or ""
                end
                local result = handler(args_str)
                if result then
                    print(result)
                end
                return BaseCommand.CommandResult.new(false, false)
            end
        }
    end
    
    function self:_register_hook(event_name, handler)
        if not self.hooks[event_name] then
            self.hooks[event_name] = {}
        end
        table.insert(self.hooks[event_name], handler)
    end
    
    function self:_register_completer(completer)
        if not self.completers then
            self.completers = {}
        end
        table.insert(self.completers, completer)
    end
    
    -- Central gate: should this plugin load?
    -- PLUGINS_ALLOW: if set, only listed plugins load
    -- PLUGINS_DENY: if set, listed plugins NEVER load (deny wins)
    function self:_should_load_plugin(name)
        local denied = config.plugins_deny()
        if denied[name] then
            return false
        end
        local allowed = config.plugins_allow()
        if allowed and not allowed[name] then
            return false
        end
        return true
    end
    
    function self:load_plugins()
        -- Load plugins from three sources (priority order):
        -- 1. Local .aicoder/plugins/ (project overrides)
        -- 2. Global ~/.config/luna/plugins/ (user-wide overrides)
        -- 3. Bundled ./plugins/ (built-in defaults)
        -- PLUGINS_ALLOW / PLUGINS_DENY env vars control which plugins load
        
        local total_start = datetime.get_time()
        
        if config.debug() then
            log.info("[i] Loading plugins...")
            log.info("[env] PLUGINS_ALLOW=" .. tostring(os.getenv("PLUGINS_ALLOW")))
            log.info("[env] PLUGINS_DENY=" .. tostring(os.getenv("PLUGINS_DENY")))
            log.info("[env] TOOLS_ALLOW=" .. tostring(os.getenv("TOOLS_ALLOW")))
            log.info("[env] TOOLS_DENY=" .. tostring(os.getenv("TOOLS_DENY")))
        end
        
        -- 1. Load local plugins first
        self:_load_plugins_from_dir(self.plugins_dir)
        
        -- 2. Load global plugins, skip if already loaded locally
        self:_load_plugins_from_dir(self.global_plugins_dir)
        
        -- 3. Load bundled plugins, skip if already loaded locally or globally
        self:_load_plugins_from_dir(self.bundled_plugins_dir)
        
        -- Count total loaded plugins
        local count = 0
        for _ in pairs(self.loaded_plugin_names) do count = count + 1 end
        
        local total_time = datetime.get_time() - total_start
        if config.debug() then
            log.info(string.format("[+] Plugins loaded in %.3fs (%d plugins)", total_time, count))
        end
    end
    
    function self:_load_plugins_from_dir(dir)
        local file_utils = require("utils.file_utils")
        local files = file_utils.list_lua_files(dir)
        
        for _, file in ipairs(files) do
            local basename = file:match("([^/]+)%.lua$")
            if basename then
                -- Skip if already loaded from a higher-priority tier
                if self.loaded_plugin_names[basename] then
                    goto continue
                end
                
                -- Central gate: check PLUGINS_ALLOW / PLUGINS_DENY
                if not self:_should_load_plugin(basename) then
                    goto continue
                end
                
                -- Actually load the plugin
                self:_load_plugin_file(file, basename)
            end
            
            ::continue::
        end
    end
    
    function self:_load_plugin_file(file, basename)
        local load_start = datetime.get_time()
        local ok, err = pcall(function()
            local chunk, load_err = loadfile(file)
            if load_err then
                error("Failed to load plugin " .. basename .. ": " .. load_err)
            end
            
            local plugin_module = chunk()
            if type(plugin_module) == "function" then
                local plugin = plugin_module(self.context)
                if plugin then
                    table.insert(self.plugins, plugin)
                end
            elseif type(plugin_module) == "table" then
                if plugin_module.create_plugin then
                    plugin_module:create_plugin(self.context)
                elseif plugin_module.setup then
                    plugin_module:setup(self.context)
                end
            end
        end)
        local load_time = datetime.get_time() - load_start
        
        if not ok then
            log.error("Plugin " .. basename .. " failed to load: " .. tostring(err))
        else
            self.loaded_plugin_names[basename] = true
            if config.debug() then
                log.info(string.format("[+] Loaded plugin: %s (%.3fs)", basename, load_time))
            end
        end
    end
    
    function self:get_tools()
        local result = {}
        for name, tool in pairs(self.tools) do
            result[name] = tool
        end
        return result
    end
    
    -- Alias for compatibility
    function self:get_plugin_tools()
        return self:get_tools()
    end
    
    function self:get_plugin_commands()
        return self:get_commands()
    end
    
    function self:get_commands()
        local result = {}
        for name, cmd in pairs(self.commands) do
            result[name] = cmd
        end
        return result
    end
    
    function self:call_hooks(event_name, arg1, arg2, arg3, arg4, arg5)
        if not self.hooks[event_name] then
            return
        end
        
        local results = {}
        for _, handler in ipairs(self.hooks[event_name]) do
            local ok, result = pcall(function()
                return handler(arg1, arg2, arg3, arg4, arg5)
            end)
            if not ok then
                log.error("Hook " .. event_name .. " failed: " .. tostring(result))
            elseif result ~= nil then
                table.insert(results, result)
            end
        end
        return results
    end
    
    function self:call_hooks_with_return(event_name, value, extra)
        if not self.hooks[event_name] then
            return value
        end
        
        local result = value
        for _, handler in ipairs(self.hooks[event_name]) do
            local ok, new_val = pcall(function()
                return handler(result, extra)
            end)
            if ok and new_val ~= nil then
                result = new_val
            end
        end
        return result
    end
    
    function self:get_completers()
        return self.completers or {}
    end
    
    function self:cleanup()
        for _, handler in ipairs(self.cleanup_handlers) do
            local ok, err = pcall(handler)
            if not ok then
                log.error("Cleanup handler failed: " .. tostring(err))
            end
        end
    end

    -- Load a single plugin file
    function self:_load_single_plugin(path, name)
        local ok, err = pcall(function()
            local plugin = dofile(path)
            if type(plugin) == "function" then
                plugin(self.context)
            elseif type(plugin) == "table" then
                if plugin.setup then
                    plugin:setup(self.context)
                elseif plugin.create_plugin then
                    plugin:create_plugin(self.context)
                end
            end
            self.plugins[name] = {path = path, name = name}
        end)
        if not ok then
            log.error("Failed to load plugin " .. name .. ": " .. tostring(err))
        end
    end

    -- Sort key for consistent ordering
    function M.sort_key(name)
        return (name or ""):lower()
    end

    -- Public register_* aliases (some plugins use these directly)
    function self:register_tool(name, fn, desc, params, auto_approved, format_args, generate_preview)
        return self:_register_tool(name, fn, desc, params, auto_approved, format_args, generate_preview)
    end

    function self:register_command(name, handler, desc)
        return self:_register_command(name, handler, desc)
    end

    function self:register_hook(event_name, handler)
        return self:_register_hook(event_name, handler)
    end

    function self:register_completer(completer)
        return self:_register_completer(completer)
    end
    
    return self
end

M.new = new

return M