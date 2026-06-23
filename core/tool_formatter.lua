-- Tool output formatter
-- Ported from Python core/tool_formatter.py

local config = require("core.config")

local M = {}

-- Class-style alias for 1-1 parity with Python's ToolFormatter class
M.ToolFormatter = M

function M.colorize_diff(diff_output)
    local lines = {}
    for line in diff_output:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    local colored_lines = {}
    local colors = config.colors

    for _, line in ipairs(lines) do
        -- Skip diff header lines
        if line:sub(1, 3) == "---" or line:sub(1, 3) == "+++" then
            -- skip
        elseif line:sub(1, 1) == "-" then
            table.insert(colored_lines, colors.red .. line .. colors.reset)
        elseif line:sub(1, 1) == "+" then
            table.insert(colored_lines, colors.green .. line .. colors.reset)
        elseif line:sub(1, 2) == "@@" then
            table.insert(colored_lines, colors.cyan .. line .. colors.reset)
        else
            table.insert(colored_lines, line)
        end
    end

    return table.concat(colored_lines, "\n")
end

function M.format_for_ai(result)
    if type(result) == "table" and result.detailed then
        return result.detailed
    end
    if type(result) == "table" then
        return result.content or tostring(result)
    end
    return tostring(result)
end

function M.format_for_display(result, show_detail)
    show_detail = show_detail or false

    if type(result) ~= "table" then
        return tostring(result)
    end

    if show_detail and result.detailed then
        return result.detailed
    elseif result.simple then
        return result.simple
    elseif result.content then
        return result.content
    end

    return nil
end

function M.truncate_output(content, max_length)
    max_length = max_length or 10000
    if not content then
        return ""
    end
    if #content > max_length then
        return content:sub(1, max_length) .. "\n... (truncated)"
    end
    return content
end

function M.format_file_result(result)
    if not result then
        return ""
    end
    if result.error then
        return "Error: " .. result.error
    end
    if result.content then
        return result.content
    end
    return tostring(result)
end

function M.format_command_result(result)
    if not result then
        return ""
    end
    if result.error then
        return "Error: " .. result.error
    end
    local output = result.stdout or ""
    if result.stderr and result.stderr ~= "" then
        output = output .. "\nStderr: " .. result.stderr
    end
    return output
end

-- Format a preview for approval
function M.format_preview(preview, file_path)
    local lines = {}
    local title = file_path or "Preview"
    local colors = config.colors or {}
    table.insert(lines, (colors.cyan or "") .. "[PREVIEW] " .. title .. (colors.reset or ""))
    table.insert(lines, "")
    if type(preview) == "table" then
        table.insert(lines, preview.content or "")
    else
        table.insert(lines, tostring(preview))
    end
    return table.concat(lines, "\n")
end

-- Format a label with consistent alignment
function M._format_label(key)
    local formatted = key:sub(1, 1):upper() .. key:sub(2):gsub("_", " ")
    return formatted .. ":"
end

local _json_encode = require("utils.json").encode

-- Format value for AI consumption (never truncates)
function M._format_value_for_ai(value)
    if value == nil then return " null" end
    if type(value) == "boolean" then return " " .. tostring(value) end
    if type(value) == "number" then return " " .. tostring(value) end
    if type(value) == "string" then return " " .. value end
    if _json_encode then
        local ok, encoded = pcall(_json_encode, value)
        if ok then return " " .. encoded end
    end
    return " " .. tostring(value)
end

-- Format a value for display
function M._format_value(value)
    if value == nil then return " null" end
    if type(value) == "boolean" then return " " .. tostring(value) end
    if type(value) == "number" then return " " .. tostring(value) end
    if type(value) == "string" then
        if not config.detail_mode and #value > 100 then
            return " " .. value:sub(1, 97) .. "..."
        end
        return " " .. value
    end
    if _json_encode then
        local ok, encoded = pcall(_json_encode, value)
        if ok then
            if not config.detail_mode and #encoded > 100 then
                return " " .. encoded:sub(1, 97) .. "..."
            end
            return " " .. encoded
        end
    end
    return " " .. tostring(value)
end

return M
