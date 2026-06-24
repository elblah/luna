-- Command execution utility

local M = {}

local file_utils = require("utils.file_utils")

-- Get temp directory (uses per-instance isolated dir if available)
local function get_tmp_dir()
    local ok, config = pcall(require, "core.config")
    if ok and config.get_tmp_dir() then
        return config.get_tmp_dir()
    end
    local temp_utils = require("utils.temp_file_utils")
    return temp_utils.get_temp_dir()
end

-- Create temp file in isolated dir
function M.tmpname()
    local tmp_dir = get_tmp_dir()
    return tmp_dir .. "/luna-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
end

function M.exec(command, timeout, cwd)
    timeout = tonumber(timeout) or 30
    local tmp = M.tmpname()
    local sh = tmp .. ".sh"
    local out = tmp .. ".out"
    local ec = tmp .. ".ec"

    -- Ensure temp directory exists (subdirs like /tmp/luna-xxx/ may not exist)
    file_utils.ensure_parent_dir(tmp)

    -- Write command to temp script file
    local f = io.open(sh, "w")
    if not f then
        return { stdout = "", exit_code = 127, error = "Failed to create temp file: " .. sh }
    end
    if cwd then
        f:write("cd " .. cwd .. "\n")
    end
    f:write(command .. "\n")
    f:close()

    -- Execute with timeout: stdout -> out file, exit code -> ec file
    local runner = "timeout " .. timeout .. " bash " .. sh .. " > " .. out .. " 2>&1; echo $? > " .. ec
    os.execute(runner)

    -- Read stdout
    local stdout = ""
    local of = io.open(out)
    if of then
        stdout = of:read("*a") or ""
        of:close()
    end

    -- Read exit code
    local exit_code = 0
    local ef = io.open(ec)
    if ef then
        exit_code = tonumber(ef:read("*a")) or 0
        ef:close()
    end

    -- Cleanup
    os.remove(tmp)
    os.remove(sh)
    os.remove(out)
    os.remove(ec)

    return { stdout = stdout, exit_code = exit_code }
end

return M
