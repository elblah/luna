-- Temporary file utilities
-- Ported from Python utils/temp_file_utils.py

local os = require("os")

local M = {}

local file_utils = require("utils.file_utils")

function M.get_temp_dir()
    -- Try system /tmp first
    local handle = io.popen("mkdir -p /tmp 2>/dev/null && echo ok")
    if handle then
        local result = handle:read("*all"):match("ok")
        handle:close()
        if result then return "/tmp" end
    end

    -- Try TMPDIR env var
    local tmp_dir = os.getenv("TMPDIR")
    if tmp_dir then
        handle = io.popen("mkdir -p " .. tmp_dir .. " 2>/dev/null && echo ok")
        if handle then
            local result = handle:read("*all"):match("ok")
            handle:close()
            if result then return tmp_dir end
        end
    end

    -- Fallback to local ./tmp (Termux, etc)
    local local_tmp = "./tmp"
    handle = io.popen("mkdir -p " .. local_tmp .. " 2>/dev/null && echo ok")
    if handle then
        local result = handle:read("*all"):match("ok")
        handle:close()
        if result then return local_tmp end
    end

    return "./tmp"
end

function M.create_temp_file(prefix, suffix)
    prefix = prefix or "temp"
    suffix = suffix or ""
    local temp_dir = M.get_temp_dir()

    math.randomseed(os.time() + os.clock() * 1000000)
    local random_suffix = string.format("%08x", math.random(0, 0xFFFFFFFF))

    local filename = temp_dir .. "/" .. prefix .. "_" .. random_suffix .. suffix
    return filename
end

function M.cleanup_old_temp_files(prefix, max_age_hours)
    prefix = prefix or "temp"
    max_age_hours = max_age_hours or 24
    local temp_dir = M.get_temp_dir()

    -- Find and remove old temp files
    local cmd = "find " .. temp_dir .. " -name '" .. prefix .. "*' -mmin +" .. (max_age_hours * 60) .. " -delete 2>/dev/null"
    os.execute(cmd)
end

-- Delete a single file (parity with Python's delete_file)
function M.delete_file(path)
    if not path then return end
    os.remove(path)
end

-- Synchronous alias for delete_file
M.delete_file_sync = M.delete_file

-- Write to a temp file (parity with Python's write_temp_file)
function M.write_temp_file(path, content)
    if not path then return end
    local dir = path:match("(.*)/[^/]+$")
    if dir and dir ~= "" then
        file_utils.mkdir_p(dir)
    end
    local f = io.open(path, "w")
    if f then
        f:write(content or "")
        f:close()
    end
end

return M
