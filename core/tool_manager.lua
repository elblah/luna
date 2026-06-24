-- Tool manager for Luna

local M = {}

-- Class-style alias for 1-1 parity with Python's ToolManager class
M.ToolManager = M

local config = require("core.config")
local log = require("utils.log")

-- Tool module names, loaded lazily in _register_internal_tools
local TOOL_MODULES = {"read_file", "write_file", "edit_file", "list_directory", "grep", "run_shell_command"}

local function new(stats)
    local self = {
        stats = stats,
        tools = {},
        read_files = {},
        plugin_system = nil,
        _tool_modules = {},
    }
    
    function self:set_plugin_system(ps)
        self.plugin_system = ps
        if self._tool_modules.write_file then
            self._tool_modules.write_file.set_plugin_system(ps)
        end
        if self._tool_modules.edit_file then
            self._tool_modules.edit_file.set_plugin_system(ps)
        end
    end
    
    function self:_register_internal_tools()
        -- Load tool modules lazily
        for _, name in ipairs(TOOL_MODULES) do
            self._tool_modules[name] = require("tools." .. name)
        end
        
        local all_tools = {
            read_file = self._tool_modules.read_file.TOOL_DEFINITION,
            write_file = self._tool_modules.write_file.TOOL_DEFINITION,
            edit_file = self._tool_modules.edit_file.TOOL_DEFINITION,
            list_directory = self._tool_modules.list_directory.TOOL_DEFINITION,
            grep = self._tool_modules.grep.TOOL_DEFINITION,
            run_shell_command = self._tool_modules.run_shell_command.TOOL_DEFINITION,
        }
        
        local allowed = config.tools_allow()
        if allowed then
            for name, tool_def in pairs(all_tools) do
                if allowed[name] then
                    self.tools[name] = tool_def
                end
            end
        else
            self.tools = all_tools
        end
        
        -- Filter by TOOLS_DENY
        local denied = config.tools_deny()
        for name in pairs(denied) do
            self.tools[name] = nil
        end
    end
    
    function self:get_tool_definitions()
        local definitions = {}
        for name, tool_def in pairs(self.tools) do
            table.insert(definitions, {
                type = "function",
                ["function"] = {
                    name = name,
                    description = tool_def.description,
                    parameters = tool_def.parameters,
                },
            })
        end
        return definitions
    end
    
    function self:execute_tool_call(tool_call, skip_preview)
        local tool_id = tool_call.id
        local func = tool_call["function"] or {}
        local name = func.name
        local args_str = func.arguments or "{}"
        
        -- Parse JSON arguments
        local ok, args = pcall(function()
            local json = require("utils.json")
            if type(args_str) == "string" then
                return json.decode(args_str)
            else
                return args_str
            end
        end)
        
        if not ok then
            return {
                tool = name or "unknown",
                friendly = "Error: Invalid JSON in tool arguments",
                detailed = "Tool execution failed: " .. tostring(args),
                success = false,
            }
        end
        
        -- Get tool definition
        local tool_def = self.tools[name]
        if not tool_def then
            return {
                tool = name,
                friendly = "Error: Unknown tool: " .. name,
                detailed = "Tool execution failed: unknown tool " .. name,
                success = false,
            }
        end
        
        -- Track read files (special case for read_file)
        if name == "read_file" and args.path then
            self.read_files[args.path] = true
            if self._tool_modules.edit_file then
                self._tool_modules.edit_file.record_read(args.path)
            end
        end
        
        -- Execute tool
        local execute_func = tool_def.execute
        if not execute_func then
            return {
                tool = name,
                friendly = "Error: Tool has no execute method",
                detailed = "Tool execution failed: no execute method",
                success = false,
            }
        end
        
        local ok2, result = pcall(function()
            return execute_func(args)
        end)
        
        if not ok2 then
            return {
                tool = name,
                friendly = ("Error executing %s: %s"):format(name, tostring(result)),
                detailed = "Tool execution failed: " .. tostring(result),
                success = false,
            }
        end
        
        return {
            tool = name,
            friendly = result.friendly or result.tool,
            detailed = result.detailed or result.friendly or "",
            success = true,
        }
    end
    
    function self:needs_approval(tool_name)
        local tool_def = self.tools[tool_name]
        if not tool_def then
            return true
        end
        return not tool_def.auto_approved
    end

    -- Check tool result size for limits
    function self:_check_size(result)
        if type(result) ~= "table" then return result end
        if result.detailed and #result.detailed > 100000 then
            result.detailed = result.detailed:sub(1, 100000) .. "\n... (truncated)"
        end
        if result.friendly and #result.friendly > 10000 then
            result.friendly = result.friendly:sub(1, 10000) .. "\n... (truncated)"
        end
        return result
    end

    -- Validate tool exists and is callable
    function self:_validate_tool(name)
        if not self.tools[name] then
            return false, "Unknown tool: " .. tostring(name)
        end
        local tool_def = self.tools[name]
        if not tool_def.execute then
            return false, "Tool has no execute function: " .. name
        end
        return true
    end

    -- Validate tool arguments against tool's parameter schema
    function self:_validate_tool_arguments(name, args)
        local tool_def = self.tools[name]
        if not tool_def then return true end
        local params = tool_def.parameters
        if not params or not params.required then return true end
        if type(args) ~= "table" then
            return false, "Tool arguments must be a table"
        end
        for _, req in ipairs(params.required) do
            if args[req] == nil then
                return false, "Missing required argument: " .. req
            end
        end
        return true
    end

    -- Parse arguments from string
    function self:_parse_arguments(args_str)
        if type(args_str) == "table" then
            return true, args_str
        end
        if type(args_str) ~= "string" or args_str == "" then
            return true, {}
        end
        local json = require("utils.json")
        local ok, decoded = pcall(json.decode, args_str)
        if not ok then
            return false, "Invalid JSON: " .. tostring(decoded)
        end
        return true, decoded
    end

    -- Format a tool result into a standardized structure
    function self:_format_result(name, success, result_or_error)
        if not success then
            return {
                tool = name,
                friendly = "Error executing " .. name .. ": " .. tostring(result_or_error),
                detailed = "Tool execution failed: " .. tostring(result_or_error),
                success = false,
            }
        end
        local r = result_or_error or {}
        if type(r) == "string" then
            return {
                tool = name,
                friendly = r,
                detailed = r,
                success = true,
            }
        end
        return {
            tool = name,
            friendly = r.friendly or r.tool or "",
            detailed = r.detailed or r.friendly or "",
            success = r.success ~= false,
        }
    end

    -- Execute tool (used when args are already parsed)
    function self:_execute_tool(name, args)
        local ok, err = self:_validate_tool(name)
        if not ok then
            return self:_format_result(name, false, err)
        end
        local tool_def = self.tools[name]
        local ok2, result = pcall(function()
            return tool_def.execute(args)
        end)
        if not ok2 then
            return self:_format_result(name, false, result)
        end
        return self:_format_result(name, true, result)
    end

    -- Initialize
    self:_register_internal_tools()

    return self
end

M.new = new

-- Execute a tool with parsed arguments dict (parity with Python)
function M:execute_tool_with_args(execution_args)
    local name = execution_args.name
    local args = execution_args.arguments
    local tool_call = {
        id = "tool_" .. name .. "_" .. tostring(args):gsub("[^%w]", ""),
        type = "function",
        ["function"] = {
            name = name,
            arguments = args,
        },
    }

    return self:execute_tool_call(tool_call)
end

local instance_mt = {
    __index = M,
}

-- Metatable for instances
local orig_new = new
new = function(stats)
    return setmetatable(orig_new(stats), instance_mt)
end
M.new = new

return M