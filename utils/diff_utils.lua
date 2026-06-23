-- Diff utilities
-- Ported from Python utils/diff_utils.py

local config = require("core.config")
local shell_utils = require("utils.shell_utils")

local M = {}

function M.colorize_diff(diff_output)
    if not diff_output or diff_output == "" then
        return ""
    end

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

-- Run `diff -u` between two file paths and return a structured result
-- matching Python's subprocess-style return: {success, exit_code, stdout, stderr}
local function run_diff(old_path, new_path)
    local cmd = string.format('diff -u "%s" "%s"', old_path, new_path)
    local handle = io.popen(cmd .. " 2>&1; echo \"__EXIT=$?\"")
    if not handle then
        return false, -1, "", "Failed to execute diff"
    end
    local output = handle:read("*all") or ""
    handle:close()
    local exit_code = 0
    local stdout = output
    local exit_marker = output:match("__EXIT=(%d+)")
    if exit_marker then
        exit_code = tonumber(exit_marker) or 0
        stdout = output:gsub("\n?__EXIT=%d+\n?$", "")
    end
    return exit_code == 0, exit_code, stdout, ""
end

-- Generate unified diff between two files (parity with Python)
function M.generate_unified_diff(old_path, new_path)
    local ok, exit_code, stdout = run_diff(old_path, new_path)
    if ok and exit_code == 0 then
        return stdout ~= "" and stdout or "No changes - content is identical"
    elseif exit_code == 1 then
        return stdout ~= "" and stdout or "Differences found (no output)"
    else
        return "Error generating diff: " .. (stdout or "")
    end
end

-- Generate unified diff and return whether changes were detected
function M.generate_unified_diff_with_status(old_path, new_path)
    local ok, exit_code, stdout = run_diff(old_path, new_path)
    if ok and exit_code == 0 then
        return {
            has_changes = false,
            diff = stdout ~= "" and stdout or "No changes - content is identical",
            exit_code = 0,
        }
    elseif exit_code == 1 then
        return {
            has_changes = true,
            diff = stdout ~= "" and stdout or "Differences found (no output)",
            exit_code = 1,
        }
    else
        return {
            has_changes = false,
            diff = "Error generating diff: " .. (stdout or ""),
            exit_code = exit_code,
        }
    end
end

function M.get_diff(old_content, new_content, old_path, new_path)
    old_path = old_path or "old"
    new_path = new_path or "new"

    -- Write temp files
    local temp = require("utils.temp_file_utils")
    local old_file = temp.create_temp_file("diff_old", ".txt")
    local new_file = temp.create_temp_file("diff_new", ".txt")

    local f = io.open(old_file, "w")
    if f then
        f:write(old_content or "")
        f:close()
    end

    f = io.open(new_file, "w")
    if f then
        f:write(new_content or "")
        f:close()
    end

    -- Run diff
    local handle = io.popen("diff -u " .. string.format("%q", old_path) .. " " .. string.format("%q", new_path) .. " 2>&1 || true")
    local output = ""
    if handle then
        output = handle:read("*all")
        handle:close()
    end

    -- Cleanup
    os.remove(old_file)
    os.remove(new_file)

    return output
end

return M
