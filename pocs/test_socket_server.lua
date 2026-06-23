#!/usr/bin/env luajit
-- Simple socket server POC for aicoder remote control

local socket = require("socket")
local cjson = require("utils.json")

-- Configuration
local PORT = 8080
local UNIX_SOCKET = nil  -- or "/tmp/aicoder.sock"

-- Command handlers
local commands = {}

commands["ping"] = function(args)
    return {ok = true, msg = "pong", time = os.time()}
end

commands["status"] = function(args)
    return {ok = true, status = "running", messages = 242}
end

commands["send"] = function(args)
    if args and args.message then
        return {ok = true, msg = "Message queued: " .. args.message}
    end
    return {ok = false, error = "no message provided"}
end

commands["quit"] = function(args)
    return {ok = true, msg = "goodbye"}
end

-- Handle client connection
local function handle_client(client)
    client:settimeout(10)  -- 10 second timeout
    
    -- Read line (JSON command)
    local line, err = client:receive()
    
    if err then
        if err ~= "timeout" then
            print("Client error: " .. err)
        end
        client:close()
        return
    end
    
    -- Parse JSON (use cjson)
    local ok, parsed = pcall(function()
        return cjson.decode(line)
    end)
    
    if not ok then
        client:send(cjson.encode({ok = false, error = "invalid json"}) .. "\n")
        client:close()
        return
    end
    
    local cmd = parsed.command or "unknown"
    local args = parsed.args or {}
    
    print("Command: " .. cmd)
    
    -- Find handler
    local handler = commands[cmd]
    local response
    
    if handler then
        local ok, result = pcall(function()
            return handler(args)
        end)
        if ok then
            response = result
        else
            response = {ok = false, error = result}
        end
    else
        response = {ok = false, error = "unknown command: " .. cmd}
    end
    
    -- Send response
    local resp_str = cjson.encode(response) .. "\n"
    client:send(resp_str)
    
    client:close()
    
    -- Check if quit
    if cmd == "quit" then
        return "quit"
    end
end

-- Main server loop
local function main()
    local server
    
    if UNIX_SOCKET then
        -- Unix socket mode
        os.remove(UNIX_SOCKET)  -- Clean up old socket
        server = socket.unix()
        server:bind(UNIX_SOCKET)
        server:listen(5)
        print("Listening on Unix socket: " .. UNIX_SOCKET)
    else
        -- TCP mode
        server = socket.tcp()
        server:setoption("reuseaddr", true)
        server:bind("*", PORT)
        server:listen(5)
        print("Listening on port: " .. PORT)
    end
    
    print("Socket server ready")
    print("Test with: echo '{\"command\":\"ping\"}' | nc localhost " .. PORT)
    print("Press Ctrl+C to stop")
    print("")
    
    while true do
        local client, err = server:accept()
        
        if err then
            if err ~= "timeout" then
                print("Accept error: " .. err)
            end
        else
            local should_quit = handle_client(client)
            if should_quit == "quit" then
                print("Quit command received")
                break
            end
        end
    end
    
    server:close()
    
    if UNIX_SOCKET then
        os.remove(UNIX_SOCKET)
    end
    
    print("Server stopped")
end

main()