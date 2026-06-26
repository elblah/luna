-- Tool Executor for Luna

local M = {}

-- Class-style alias for 1-1 parity with Python's ToolExecutor class
M.ToolExecutor = M

local config = require("core.config")
local log = require("utils.log")

function M.new(tool_manager, message_history, plugin_system)
    local self = {
        tool_manager = tool_manager,
        message_history = message_history,
        _guidance_mode = false,
        plugin_system = plugin_system,
    }
    
    function self:is_guidance_mode()
        return self._guidance_mode
    end
    
    function self:clear_guidance_mode()
        self._guidance_mode = false
    end
    
    function self:execute_tool_calls(tool_calls)
        if not tool_calls or type(tool_calls) ~= "table" or #tool_calls == 0 then
            return
        end
        
        local tool_results = {}
        
        for i, tool_call in ipairs(tool_calls) do
            local result = self:_execute_single_tool_call(tool_call)
            if result then
                table.insert(tool_results, result)
            end
            
            -- Stop if guidance mode was activated
            if self._guidance_mode then
                -- Add cancelled results for remaining tools
                for j = i + 1, #tool_calls do
                    table.insert(tool_results, {
                        tool_call_id = tool_calls[j].id or "",
                        content = "Tool execution cancelled - guidance requested",
                    })
                end
                break
            end
        end
        
        -- Add all tool results to message history
        self.message_history:add_tool_results(tool_results)
        
        -- Call plugin hook
        if self.plugin_system then
            self.plugin_system:call_hooks("after_tool_results", tool_results)
        end
    end
    
    function self:_execute_single_tool_call(tool_call)
        local func = tool_call["function"] or {}
        local tool_name = func.name
        
        if not tool_name then
            local id = tool_call.id or ""
            log.error("[x] Tool call missing function name")
            return {
                tool_call_id = id,
                content = "Error: Tool call missing 'function.name' field.",
            }
        end
        
        -- Get tool definition
        local tool_def = self.tool_manager.tools[tool_name]
        if not tool_def then
            return self:_handle_tool_not_found(tool_name, tool_call.id or "")
        end
        
        -- Parse arguments
        local args = self:_parse_tool_arguments(func.arguments or "{}")
        
        -- Display tool info
        print()
        log.printc("[*] Tool: " .. tool_name, {color = "yellow", bold = true})
        
        -- Generate and display preview, or show formatted arguments
        if tool_def.generatePreview then
            local result = self:_handle_preview_display(tool_def, args, tool_call.id or "")
            if result == false then
                return nil
            elseif type(result) == "table" then
                return result
            end
        elseif tool_def.formatArguments then
            local formatted_args = tool_def.formatArguments(args)
            if formatted_args and formatted_args ~= "" then
                log.printc(formatted_args, {color = "cyan"})
            end
        end
        
        -- Check approval
        if not self:_get_tool_approval(tool_name, args) then
            return {
                tool_call_id = tool_call.id or "",
                content = "Tool execution cancelled by user",
            }
        end
        
        -- Execute tool
        local result = self:_execute_tool(tool_name, args, tool_call.id or "")
        
        -- Display result (like v3)
        self:display_tool_result(result, tool_def)
        
        return result
    end
    
    function self:_parse_tool_arguments(args_str)
        if type(args_str) == "table" then
            return args_str
        end
        
        local ok, result = pcall(function()
            local json = require("utils.json")
            return json.decode(args_str)
        end)
        
        if ok then
            return result
        end
        return {}
    end
    
    function self:_handle_tool_not_found(tool_name, tool_call_id)
        log.error("[x] Tool not found: " .. tool_name)
        return {
            tool_call_id = tool_call_id,
            content = "Error: Tool '" .. tool_name .. "' does not exist.",
        }
    end
    
    function self:_should_show_preview(tool_def, args)
        return tool_def and tool_def.generatePreview ~= nil
    end
    
    function self:_handle_preview_display(tool_def, args, tool_call_id)
        local ok, preview_result = pcall(function()
            return tool_def.generatePreview(args)
        end)
        
        if not ok then
            log.error("Preview generation failed: " .. tostring(preview_result))
            return true
        end
        
        if not preview_result then
            return true
        end
        
        -- If can't approve (safety violation), show content directly
        if not preview_result.can_approve then
            if preview_result.content then
                print(preview_result.content)
            end
            return {
                tool_call_id = tool_call_id,
                content = preview_result.content or "",
                friendly = preview_result.tool and (preview_result.tool .. " blocked") or "Blocked",
            }
        end
        
        -- Display preview content (just [PREVIEW] Preview - path is in content)
        local preview_content = preview_result.content or ""
        local colors = config.colors
        print(colors.cyan .. "[PREVIEW] Preview" .. colors.reset)
        print()
        
        if preview_content then
            print(preview_content)
        end
        
        return true
    end
    
    function self:_get_tool_approval(tool_name, args)
        -- Check if tool is auto-approved
        local tool_def = self.tool_manager.tools[tool_name]
        if tool_def and tool_def.auto_approved then
            return true
        end
        
        -- YOLO mode = auto-approve
        if config.yolo_mode() then
            return true
        end
        
        -- Get approval
        while true do
            io.write("Approve [Y/n]: ")
            local approval = io.read("*line")
            
            if not approval then
                -- Ctrl+C during approval - treat as denial
                print()
                return false
            end
            
            approval = approval:match("^%s*(.*%S)") or ""
            
            -- Empty defaults to yes
            if approval == "" then
                self._has_guidance = false
                return true
            end
            
            -- Handle yolo command
            if approval == "yolo" then
                config.set_yolo_mode(true)
                log.success("[*] YOLO mode ENABLED")
                return true
            end

            -- Handle detail command
            if approval == "detail" then
                config.set_detail_mode(true)
                log.success("[*] Detail mode ENABLED")
                return true
            end
            
            -- Parse + modifier for guidance
            local has_guidance = approval:match("%+$")
            local base_answer = has_guidance and approval:gsub("%+$", "") or approval
            
            -- Canonical answers (a = yes, d = no)
            local canonical = base_answer
            if base_answer == "a" then
                canonical = "y"
            elseif base_answer == "d" then
                canonical = "n"
            end
            
            -- Validate input
            if canonical == "y" or canonical == "n" or canonical == "yes" or canonical == "no" then
                -- User denied
                if canonical == "n" or canonical == "no" then
                    log.error("[x] Tool execution cancelled.")
                    if has_guidance then
                        self._guidance_mode = true
                    end
                    print()
                    return false
                end
                
                -- User approved
                if has_guidance then
                    self._guidance_mode = true
                end
                return true
            end
            
            log.error("Invalid option. Valid: Y, n, a, d, yes, no, yolo, detail (append + for guidance mode)")
        end
    end
    
    function self:_execute_tool(tool_name, args, tool_call_id)
        local exec_args = {
            name = tool_name,
            arguments = args,
        }
        
        local result = self.tool_manager:execute_tool_with_args(exec_args)
        
        -- Format result (display handled by display_tool_result)
        local detailed = result.detailed or result.content or ""

        return {
            tool_call_id = tool_call_id,
            content = detailed,  -- add_tool_results expects 'content'
            detailed = detailed,
            friendly = result.friendly or result.tool or "Done",
        }
    end

    function self:display_tool_result(result, tool_def)
        if tool_def and tool_def.hide_results then
            log.success("[*] Done")
        else
            if config.detail_mode() then
                log.print(result.detailed)
                log.print(result.friendly)
            else
                log.print(result.friendly)
            end
        end
    end

    return self
end

return M
