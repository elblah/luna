#!/usr/bin/env luajit
-- Luna - AI Coder in Pure Lua
-- Main entry point

-- Get absolute path to this script's directory
local script_path = arg[0] or ""
local script_dir = script_path:match("(.*/)") or "."
if script_dir == "" then script_dir = "." end
-- Make available to other modules (e.g. plugin_system for bundled plugins)
_G.SCRIPT_DIR = script_dir

package.path = package.path .. ";" .. script_dir .. "/?.lua;" .. script_dir .. "/core/?.lua;" .. script_dir .. "/tools/?.lua;" .. script_dir .. "/utils/?.lua;" .. script_dir .. "/commands/?.lua"

-- Extend string prototype if trim doesn't exist
if not string.trim then
    function string.trim(s)
        return s:match("^%s*(.-)%s*$")
    end
end

-- Signal handling: Ctrl+C counter, only /quit exits
local ctrl_c_count = 0
local MAX_CTRL_C_TO_EXIT = tonumber(os.getenv("LUNA_MAX_CTRL_C") or "7")

pcall(function()
    local ffi = require("ffi")
    ffi.cdef[[
        void (*signal(int signum, void (*handler)(int)))(int);
        typedef void (*sighandler_t)(int);
    ]]
    
    -- Signal handler: increment counter, exit if too many
    local handler = ffi.cast("sighandler_t", function(sig)
        ctrl_c_count = ctrl_c_count + 1
        if ctrl_c_count >= MAX_CTRL_C_TO_EXIT then
            io.write("\nCtrl+C pressed " .. MAX_CTRL_C_TO_EXIT .. " times... exiting...\n")
            os.exit(1)
        end
    end)
    
    -- Ignore handlers for TSTP and QUIT
    local SIG_IGN = ffi.cast("sighandler_t", 1)
    
    -- SIGINT (Ctrl+C) - count it
    ffi.C.signal(2, handler)
    -- SIGTSTP (Ctrl+Z) - ignored
    ffi.C.signal(18, SIG_IGN)
    -- SIGQUIT (Ctrl+\) - ignored
    ffi.C.signal(3, SIG_IGN)
end)

-- Reset Ctrl+C counter (call after successful AI operation)
function _G.reset_ctrl_c_count()
    ctrl_c_count = 0
end

local AICoder = require("core.aicoder")
local datetime = require("utils.datetime_utils")

local function main()
    -- Create and run Luna
    local app = AICoder.new()
    
    local ok, err = pcall(function()
        app:initialize()
        
        -- Calculate and display startup time (only if AICODER_START_TIME is set)
        local start_time_str = os.getenv("AICODER_START_TIME")
        if start_time_str then
            local start_time = tonumber(start_time_str)
            if start_time then
                local startup_time = datetime.get_time() - start_time
                print(string.format("\027[96mTotal startup time: %.2f seconds\027[0m", startup_time))
            end
        end
        
        app:run()
    end)
    
    if not ok then
        print("[!] Fatal error: " .. tostring(err))
        os.exit(1)
    end
end

main()