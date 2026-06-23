-- Minimal logging utility for Luna

local M = {}

local config = require("core.config")

-- Class-style aliases for 1-1 parity with Python's LogUtils/LogOptions
M.LogUtils = M
M.LogOptions = { colors = {}, prefix = "", quiet = false, debug = false }

-- Get color code from name
local function color_code(name)
    local colors = config.colors
    return colors[name] or ""
end

-- Get colors table (parity with Python's _get_colors)
function M._get_colors()
    return config.colors
end

-- Check if debug mode is enabled (parity with Python's _is_debug)
function M._is_debug()
    return config.debug()
end

-- Get the path to the error log file
function M._get_error_log_path()
    local temp_utils = require("utils.temp_file_utils")
    local session_dir = config.session_dir and config.session_dir() or temp_utils.get_temp_dir()
    return session_dir .. "/error.log"
end

-- Append an error message + traceback to the error log
function M._append_error_log(message, traceback_str)
    local path = M._get_error_log_path()
    local f, err = io.open(path, "a")
    if not f then
        return false, err
    end
    f:write("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] " .. tostring(message or "") .. "\n")
    if traceback_str and traceback_str ~= "" then
        f:write(tostring(traceback_str) .. "\n")
    end
    f:write("\n")
    f:close()
    return true
end

-- Alias for Python's is_debug used internally
local function is_debug()
    return config.debug()
end

-- Print with optional color
function M.printc(message, opts)
    local color = nil
    local bold = false
    local debug = false
    
    if opts then
        if type(opts) == "table" then
            color = opts.color
            bold = opts.bold
            debug = opts.debug
        elseif type(opts) == "string" then
            color = opts
        end
    end
    
    if debug and not is_debug() then
        return
    end
    
    local prefix = ""
    if bold or color then
        if bold then
            prefix = prefix .. color_code("bold")
        end
        if color then
            prefix = prefix .. color_code(color)
        end
    end
    
    local suffix = ""
    if bold or color then
        suffix = color_code("reset")
    end
    
    print(prefix .. message .. suffix)
end

-- Convenience methods
function M.print(msg)
    print(msg or "")
end

function M.success(msg)
    M.printc(msg, {color = "green", bold = true})
end

function M.error(msg)
    M.printc(msg, {color = "red", bold = true})
end

function M.warn(msg)
    M.printc(msg, {color = "yellow", bold = true})
end

function M.info(msg)
    M.printc(msg, {color = "cyan"})
end

function M.debug(msg)
    M.printc(msg, {color = "dim", debug = true})
end

function M.tip(msg)
    M.printc(msg, {color = "brightGreen"})
end

function M.hint(msg)
    M.printc(msg, {color = "cyan", bold = true})
end

function M.note(msg)
    M.printc(msg, {color = "brightYellow"})
end

function M.dim(msg)
    M.printc(msg, {color = "dim"})
end

function M.strong(msg)
    M.printc(msg, {color = "white", bold = true})
end

-- Print in cyan (parity with Python's cyan())
function M.cyan(msg)
    M.printc(msg, {color = "cyan"})
end

return M
