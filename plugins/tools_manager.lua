-- Tools Manager Plugin - Manage available tools
--
-- Commands:
-- - /tools                          - List all tools (same as /tools list)
-- - /tools list                     - List all available tools
-- - /tools show <tool_name>         - Show detailed information about a tool
-- - /tools help                     - Show help message

local M = {}

local config = require("core.config")

function M:create_plugin(ctx)
    -- Internal storage for disabled tools
    local disabled_tools = {}
    
    local function get_all_tools()
        if not ctx.app or not ctx.app.tool_manager then
            return {}
        end
        return ctx.app.tool_manager.tools
    end
    
    local function list_tools()
        local tools = get_all_tools()
        local lines = {}
        
        local internal_tools = {}
        local plugin_tools = {}
        
        if tools and next(tools) then
            table.insert(lines, "Available Tools:")
            table.insert(lines, "")
            
            for name, tool_def in pairs(tools) do
                local tool_type = tool_def.type or "unknown"
                local description = tool_def.description or "No description"
                local auto_approved = tool_def.auto_approved or false
                local status = auto_approved and "[auto]" or "[needs approval]"
                local tool_info = string.format("  %-25s - %-50s %s", name, description:sub(1, 50), status)
                
                if tool_type == "internal" then
                    table.insert(internal_tools, {name, tool_info})
                elseif tool_type == "plugin" then
                    table.insert(plugin_tools, {name, tool_info})
                else
                    table.insert(internal_tools, {name, tool_info})
                end
            end
            
            -- Sort
            table.sort(internal_tools, function(a, b) return a[1] < b[1] end)
            table.sort(plugin_tools, function(a, b) return a[1] < b[1] end)
            
            if #internal_tools > 0 then
                table.insert(lines, "Internal Tools:")
                for _, v in ipairs(internal_tools) do
                    table.insert(lines, v[2])
                end
                table.insert(lines, "")
            end
            
            if #plugin_tools > 0 then
                table.insert(lines, "Plugin Tools:")
                for _, v in ipairs(plugin_tools) do
                    table.insert(lines, v[2])
                end
                table.insert(lines, "")
            end
            
            table.insert(lines, "Total: " .. tostring(next(tools) and #tools or 0) .. " tools")
        end
        
        -- Add disabled tools section
        if disabled_tools and next(disabled_tools) then
            table.insert(lines, "")
            table.insert(lines, "Disabled Tools:")
            table.insert(lines, "")
            
            local disabled_internal = {}
            local disabled_plugin = {}
            
            for name, tool_def in pairs(disabled_tools) do
                local tool_type = tool_def.type or "unknown"
                local description = tool_def.description or "No description"
                local auto_approved = tool_def.auto_approved or false
                local status = auto_approved and "[auto]" or "[needs approval]"
                local tool_info = string.format("  %-25s - %-50s %s", name, description:sub(1, 50), status)
                
                if tool_type == "internal" then
                    table.insert(disabled_internal, tool_info)
                else
                    table.insert(disabled_plugin, tool_info)
                end
            end
            
            table.sort(disabled_internal)
            table.sort(disabled_plugin)
            
            if #disabled_internal > 0 then
                table.insert(lines, "  Internal (disabled):")
                for _, info in ipairs(disabled_internal) do
                    table.insert(lines, info)
                end
            end
            
            if #disabled_plugin > 0 then
                if #disabled_internal > 0 then
                    table.insert(lines, "")
                end
                table.insert(lines, "  Plugin (disabled):")
                for _, info in ipairs(disabled_plugin) do
                    table.insert(lines, info)
                end
            end
            
            local count = 0
            for _ in pairs(disabled_tools) do count = count + 1 end
            table.insert(lines, "")
            table.insert(lines, "Total disabled: " .. count .. " tools")
            table.insert(lines, "")
            table.insert(lines, "Tip: Use /tools enable <tool_name> to re-enable specific tools")
            table.insert(lines, "Tip: Use /tools enable-all to re-enable all disabled tools")
        end
        
        return table.concat(lines, "\n")
    end
    
    local function show_tool(tool_name)
        local tools = get_all_tools()
        local tool_def = tools and tools[tool_name]
        
        if not tool_def then
            if disabled_tools and disabled_tools[tool_name] then
                return "Tool '" .. tool_name .. "' is currently DISABLED\n\nTo enable it, use: /tools enable " .. tool_name
            end
            return "Tool '" .. tool_name .. "' not found\n\nUse /tools list to see all available tools"
        end
        
        local lines = {}
        table.insert(lines, "Tool: " .. tool_name)
        table.insert(lines, string.rep("=", 60))
        table.insert(lines, "")
        
        -- Type
        local tool_type = tool_def.type or "unknown"
        table.insert(lines, "Type: " .. tool_type)
        table.insert(lines, "")
        
        -- Description
        local description = tool_def.description or "No description"
        table.insert(lines, "Description:")
        table.insert(lines, "  " .. description)
        table.insert(lines, "")
        
        -- Auto-approved
        local auto_approved = tool_def.auto_approved or false
        table.insert(lines, "Auto-approved: " .. (auto_approved and "Yes" or "No"))
        table.insert(lines, "")
        
        -- Parameters
        local parameters = tool_def.parameters or {}
        if parameters and next(parameters) then
            table.insert(lines, "Parameters:")
            local props = parameters.properties or {}
            local required = parameters.required or {}
            
            -- Build required set
            local req_set = {}
            for _, r in ipairs(required) do req_set[r] = true end
            
            if props and next(props) then
                for param_name, param_info in pairs(props) do
                    local param_type = param_info.type or "unknown"
                    local param_desc = param_info.description or ""
                    local is_required = req_set[param_name]
                    local req_marker = is_required and "*" or ""
                    
                    table.insert(lines, "  " .. param_name .. req_marker)
                    table.insert(lines, "    Type: " .. param_type)
                    
                    if param_desc and param_desc ~= "" then
                        table.insert(lines, "    Description: " .. param_desc)
                    end
                    
                    if param_info.default ~= nil then
                        table.insert(lines, "    Default: " .. tostring(param_info.default))
                    end
                    
                    table.insert(lines, "")
                end
            else
                table.insert(lines, "  No parameters")
            end
        else
            table.insert(lines, "Parameters: None")
        end
        table.insert(lines, "")
        
        -- Footer
        table.insert(lines, "Legend: * = required parameter")
        table.insert(lines, "")
        table.insert(lines, "To disable this tool, use: /tools disable " .. tool_name)
        
        return table.concat(lines, "\n")
    end
    
    local function disable_tool(tool_name)
        if not tool_name or tool_name == "" then
            return "Error: Tool name is required\nUsage: /tools disable <tool_name>"
        end
        
        local tools = get_all_tools()
        
        if not tools[tool_name] then
            return "Error: Tool '" .. tool_name .. "' not found\n\nUse /tools list to see all available tools"
        end
        
        if disabled_tools and disabled_tools[tool_name] then
            return "Error: Tool '" .. tool_name .. "' is already disabled"
        end
        
        -- Store the tool definition
        disabled_tools[tool_name] = tools[tool_name]
        
        -- Remove from tool_manager.tools
        tools[tool_name] = nil
        
        return "Tool '" .. tool_name .. "' has been disabled\n\nTo enable it, use: /tools enable " .. tool_name
    end
    
    local function enable_tool(tool_name)
        if not tool_name or tool_name == "" then
            return "Error: Tool name is required\nUsage: /tools enable <tool_name>"
        end
        
        if not disabled_tools or not disabled_tools[tool_name] then
            return "Error: Tool '" .. tool_name .. "' is not disabled\n\nUse /tools list to see all available tools"
        end
        
        -- Restore to tool_manager.tools
        local tools = get_all_tools()
        tools[tool_name] = disabled_tools[tool_name]
        
        -- Remove from disabled
        disabled_tools[tool_name] = nil
        
        return "Tool '" .. tool_name .. "' has been enabled"
    end
    
    local function disable_all_tools()
        local tools = get_all_tools()
        local count = 0
        
        for name, tool_def in pairs(tools) do
            disabled_tools[name] = tool_def
            count = count + 1
        end
        
        -- Clear all tools
        for name in pairs(tools) do
            tools[name] = nil
        end
        
        return string.format("WARNING: All %d tools have been disabled!\n\nTo re-enable them, use:\n  /tools enable-all (re-enable all)\n  /tools enable <tool_name> (re-enable specific)", count)
    end
    
    local function enable_all_tools()
        if not disabled_tools or not next(disabled_tools) then
            return "No tools are currently disabled"
        end
        
        local tools = get_all_tools()
        local count = 0
        
        for name, tool_def in pairs(disabled_tools) do
            tools[name] = tool_def
            disabled_tools[name] = nil
            count = count + 1
        end
        
        local tool_count = 0
        for _ in pairs(tools) do tool_count = tool_count + 1 end
        
        return string.format("Successfully re-enabled %d tools\n\nTotal available tools: %d", count, tool_count)
    end
    
    local function handle_tools_command(args_str)
        if not args_str or args_str == "" or args_str:match("^%s*$") then
            return list_tools()
        end
        
        -- Parse command
        local parts = {}
        for part in args_str:gmatch("%S+") do
            table.insert(parts, part)
        end
        
        local command = parts[1] and parts[1]:lower() or ""
        local rest = parts[2] or ""
        
        if command == "list" then
            return list_tools()
        elseif command == "show" then
            if rest == "" then
                return "Error: Tool name required\nUsage: /tools show <tool_name>"
            end
            return show_tool(rest)
        elseif command == "disable" then
            if rest == "all" then
                return disable_all_tools()
            end
            if rest == "" then
                return "Error: Tool name required\nUsage: /tools disable <tool_name>"
            end
            return disable_tool(rest)
        elseif command == "enable" then
            if rest == "all" then
                return enable_all_tools()
            end
            if rest == "" then
                return "Error: Tool name required\nUsage: /tools enable <tool_name>"
            end
            return enable_tool(rest)
        elseif command == "disable-all" then
            return disable_all_tools()
        elseif command == "enable-all" then
            return enable_all_tools()
        elseif command == "help" then
            return [[Tools Manager Plugin

Manage available tools (both internal and plugin tools).

Commands:
    /tools                           - List all available tools
    /tools list                      - List all available tools
    /tools show <tool_name>          - Show detailed information about a tool
    /tools disable <tool_name>       - Disable a tool (temporarily remove it)
    /tools enable <tool_name>        - Enable a previously disabled tool
    /tools disable-all               - Disable ALL tools (use with caution!)
    /tools enable-all                - Enable ALL disabled tools
    /tools help                      - Show this help message

Examples:
    /tools                           - Show all tools (including disabled ones)
    /tools show read_file            - Show details about read_file tool
    /tools disable web_search        - Disable web_search tool
    /tools enable web_search         - Enable web_search tool again
    /tools disable-all               - Disable all tools at once
    /tools enable-all                - Re-enable all disabled tools

Notes:
    - Disabled tools are shown in a separate "Disabled Tools" section
    - The AI cannot use disabled tools until they are re-enabled]]
        else
            -- Unknown command - try showing it as a tool name
            if tools and tools[command] then
                return show_tool(command)
            else
                return "Unknown command: " .. command .. "\n\nUse /tools help for usage information"
            end
        end
    end
    
    -- Register the /tools command
    ctx:register_command("/tools", handle_tools_command, "Manage available tools")
    
    if config.debug() then
        print("  - /tools command")
    end
    
    return true
end

return M
