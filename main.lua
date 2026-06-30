#!/usr/bin/env luajit
-- Luna - AI Coder in Pure Lua
-- Main entry point

-- Get absolute path to this script's directory
local script_path = arg[0] or ""
local script_dir = script_path:match("(.*/)") or "."
if script_dir == "" then script_dir = "." end
-- Strip trailing slash to avoid // in concatenated paths
script_dir = script_dir:gsub("/+$", "")
-- Make available to other modules (e.g. plugin_system for bundled plugins)
_G.SCRIPT_DIR = script_dir

package.path = package.path .. ";" .. script_dir .. "/?.lua;" .. script_dir .. "/core/?.lua;" .. script_dir .. "/tools/?.lua;" .. script_dir .. "/utils/?.lua;" .. script_dir .. "/commands/?.lua"

-- Extend string prototype if trim doesn't exist
if not string.trim then
    function string.trim(s)
        return s:match("^%s*(.-)%s*$")
    end
end

-- stdin utils for TTY detection
local stdin_utils = require("utils.stdin_utils")

-- Signal handling: Ctrl+C cancels current AI operation, never exits
-- ignore_ctrl_c = true when readline prompt is shown (don't cancel prompt)
_G.processing_cancelled = false
_G.ignore_ctrl_c = false

pcall(function()
    local ffi = require("ffi")
    ffi.cdef[[
        void (*signal(int signum, void (*handler)(int)))(int);
        typedef void (*sighandler_t)(int);
    ]]
    
    -- Signal handler: cancel AI processing, never exit
    local handler = ffi.cast("sighandler_t", function(sig)
        if _G.ignore_ctrl_c then return end
        _G.processing_cancelled = true
    end)
    
    -- Ignore handlers for TSTP and QUIT
    local SIG_IGN = ffi.cast("sighandler_t", 1)
    
    -- SIGINT (Ctrl+C) - cancel processing
    ffi.C.signal(2, handler)
    -- SIGTSTP (Ctrl+Z) - ignored
    ffi.C.signal(18, SIG_IGN)
    -- SIGQUIT (Ctrl+\) - ignored
    ffi.C.signal(3, SIG_IGN)
end)

local datetime = require("utils.datetime_utils")

-- Capture start time: prefer AICODER_START_TIME (set by shell for full-process timing),
-- otherwise capture now via same monotonic clock used by datetime.get_time()
local _start_time = tonumber(os.getenv("AICODER_START_TIME")) or datetime.get_time()

local AICoder = require("core.aicoder")

local function main()
    -- Create and run Luna
    local app = AICoder.new()
    
    local ok, err = pcall(function()
        app:initialize()
        
        -- Calculate and display startup time (only in TTY mode)
        if stdin_utils.is_stdin_tty() then
            local startup_time = datetime.get_time() - _start_time
            print(string.format("\027[96mTotal startup time: %.2f seconds\027[0m", startup_time))
        end
        
        app:run()
    end)
    
    if not ok then
        print("[!] Fatal error: " .. tostring(err))
        os.exit(1)
    end
end

main()