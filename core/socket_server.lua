-- Socket Server - Unix domain socket for external control
-- Ported from Python core/socket_server.py

local json = require("utils.json")
local os = require("os")
local socket = require("socket")
local socket_unix = require("socket.unix")
local config = require("core.config")
local log = require("utils.log")
local temp_file = require("utils.temp_file_utils")

-- Error codes
local ERR_NOT_PROCESSING = 1001
local ERR_UNKNOWN_CMD = 1002
local ERR_MISSING_ARG = 1003
local ERR_INVALID_ARG = 1004
local ERR_PERMISSION = 1101
local ERR_IO_ERROR = 1201
local ERR_INTERNAL = 1301

local MAX_INJECT_TEXT_SIZE = 10 * 1024 * 1024  -- 10MB

local M = {}

function M.response(data, error_code, error_msg)
    if error_code then
        return json.encode({
            status = "error",
            code = error_code,
            message = error_msg
        })
    end
    return json.encode({
        status = "success",
        data = data
    })
end

-- Generate random hex token
local function _gen_token_hex(n)
    local chars = "0123456789abcdef"
    local result = {}
    math.randomseed(os.time() + os.clock() * 1000000)
    for i = 1, n do
        result[i] = chars:sub(math.random(1, 16), math.random(1, 16))
    end
    return table.concat(result)
end

-- Base64 decode (returns nil on invalid input)
local function b64decode(input)
    if not input or input == "" then return nil end
    local ok, mime = pcall(require, "mime")
    if ok and mime and mime.unb64 then
        local data = mime.unb64(input)
        if data and #data > 0 then return data end
        return nil
    end
    return nil
end

local SocketServer = {}
SocketServer.__index = SocketServer

function SocketServer.new(aicoder_instance)
    local self = setmetatable({}, SocketServer)
    self.aicoder = aicoder_instance
    self.socket_path = nil
    self.server_socket = nil
    self.server_thread = nil
    self.is_running = false
    self._lock = false  -- simple flag, not thread-safe but adequate
    return self
end

-- Build a default socket path
function SocketServer:_generate_socket_path()
    local tmpdir = os.getenv("AICODER_SOCKET_DIR") or os.getenv("TMPDIR") or temp_file.get_temp_dir()
    local random_id = _gen_token_hex(3)
    local pid = tostring(os.time())  -- fallback PID proxy
    return string.format("%s/aicoder-%s-%s.socket", tmpdir, pid, random_id)
end

-- Start the socket server (background thread)
function SocketServer:start()
    if self.is_running then return end

    self.socket_path = os.getenv("AICODER_SOCKET_IPC_FILE")
    local tmpdir
    if self.socket_path then
        tmpdir = self.socket_path:match("^(.*)/")
        if not tmpdir or tmpdir == "" then tmpdir = temp_file.get_temp_dir() end
    else
        tmpdir = os.getenv("AICODER_SOCKET_DIR") or os.getenv("TMPDIR") or temp_file.get_temp_dir()
        self.socket_path = self:_generate_socket_path()
    end

    -- Make sure directory exists
    os.execute("mkdir -p " .. tmpdir)

    -- Remove old socket if exists
    os.remove(self.socket_path)

    local ok, sock = pcall(socket_unix, "stream")
    if not ok or not sock then
        log.error("[Socket] Failed to create Unix socket")
        return
    end

    local bind_ok, bind_err = pcall(function() sock:bind(self.socket_path) end)
    if not bind_ok then
        log.error("[Socket] Failed to bind: " .. tostring(bind_err))
        return
    end

    local listen_ok, listen_err = pcall(function() sock:listen(1) end)
    if not listen_ok then
        log.error("[Socket] Failed to listen: " .. tostring(listen_err))
        return
    end

    os.execute("chmod 600 " .. self.socket_path)
    self.server_socket = sock
    self.is_running = true

    if io.stdout and io.stdout.tty then
        log.info("[Socket] " .. self.socket_path)
    end
end

-- Read a single line from a client socket
function SocketServer:_read_line(client, timeout)
    client:settimeout(timeout or 3.0)
    return client:receive("*l")
end

-- Send a line to a client socket
function SocketServer:_send_line(client, data)
    client:send((data or "") .. "\n")
end

-- Process one step of the server loop (called from main loop)
function SocketServer:_server_loop_step()
    if not self.is_running or not self.server_socket then return end

    local sock = self.server_socket
    sock:settimeout(0.05)
    local client, accept_err = sock:accept()
    if not client then return end

    -- Handle client synchronously (simple)
    self:_handle_client(client)
end

-- Alias for _server_loop_step (parity with Python; in Lua the loop is stepped
-- from the main poll, so this is a one-shot equivalent).
function SocketServer:_server_loop()
    return self:_server_loop_step()
end

-- Handle one client connection
function SocketServer:_handle_client(client)
    local data = self:_read_line(client, 3.0)
    if not data or data == "" then
        self:_send_line(client, M.response(nil, ERR_INTERNAL, "Empty command"))
        client:close()
        return
    end

    if config.debug() then
        log.debug("[Socket] Cmd: " .. data)
    end

    local resp = self:_execute_command(data)
    self:_send_line(client, resp)
    client:close()
end

-- Execute a command string and return a response JSON string
function SocketServer:_execute_command(command)
    command = (command or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if command == "" then
        return M.response(nil, ERR_INTERNAL, "Empty command")
    end

    local cmd, args = command:match("^(%S+)%s*(.-)$")
    cmd = cmd or command
    args = args or ""

    local handlers = {
        is_processing = function() return self:_cmd_is_processing(args) end,
        yolo = function() return self:_cmd_yolo(args) end,
        detail = function() return self:_cmd_detail(args) end,
        sandbox = function() return self:_cmd_sandbox(args) end,
        debug = function() return self:_cmd_debug(args) end,
        status = function() return self:_cmd_status(args) end,
        stop = function() return self:_cmd_stop(args) end,
        messages = function() return self:_cmd_messages(args) end,
        inject = function() return self:_cmd_inject(args) end,
        ["inject-text"] = function() return self:_cmd_inject_text(args) end,
        process = function() return self:_cmd_process(args) end,
        command = function() return self:_cmd_command(args) end,
        save = function() return self:_cmd_save(args) end,
        kill = function() return self:_cmd_kill(args) end,
        quit = function() return self:_cmd_quit(args) end,
    }

    local handler = handlers[cmd]
    if not handler then
        return M.response(nil, ERR_UNKNOWN_CMD, "Unknown command: " .. tostring(cmd))
    end

    local ok, result = pcall(handler)
    if not ok then
        return M.response(nil, ERR_INTERNAL, tostring(result))
    end
    return result
end

-- =========================================================================
-- Command Handlers
-- =========================================================================

function SocketServer:_cmd_is_processing(args)
    local is_proc = false
    if self.aicoder.session_manager then
        is_proc = self.aicoder.session_manager.is_processing
    elseif self.aicoder.is_processing ~= nil then
        is_proc = self.aicoder.is_processing
    end
    return M.response({processing = is_proc})
end

function SocketServer:_cmd_yolo(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args == "" or args == "status" then
        return M.response({enabled = config.yolo_mode()})
    elseif args == "toggle" then
        local current = config.yolo_mode()
        config.set_yolo_mode(not current)
        return M.response({enabled = not current, message = "YOLO " .. (not current and "enabled" or "disabled")})
    elseif args == "on" then
        config.set_yolo_mode(true)
        return M.response({enabled = true, message = "YOLO enabled"})
    elseif args == "off" then
        config.set_yolo_mode(false)
        return M.response({enabled = false, message = "YOLO disabled"})
    end
    return M.response(nil, ERR_INVALID_ARG, "Usage: yolo [on|off|status|toggle]")
end

function SocketServer:_cmd_detail(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args == "" or args == "status" then
        return M.response({enabled = config.detail_mode()})
    elseif args == "toggle" then
        local current = config.detail_mode()
        config.set_detail_mode(not current)
        return M.response({enabled = not current, message = "Detail mode " .. (not current and "enabled" or "disabled")})
    elseif args == "on" then
        config.set_detail_mode(true)
        return M.response({enabled = true, message = "Detail mode enabled"})
    elseif args == "off" then
        config.set_detail_mode(false)
        return M.response({enabled = false, message = "Detail mode disabled"})
    end
    return M.response(nil, ERR_INVALID_ARG, "Usage: detail [on|off|status|toggle]")
end

function SocketServer:_cmd_sandbox(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args == "" or args == "status" then
        return M.response({enabled = not config.sandbox_disabled()})
    elseif args == "toggle" then
        local current = config.sandbox_disabled()
        config.set_sandbox_disabled(not current)
        return M.response({enabled = current, message = "Sandbox " .. (current and "enabled" or "disabled")})
    elseif args == "on" then
        config.set_sandbox_disabled(false)
        return M.response({enabled = true, message = "Sandbox enabled"})
    elseif args == "off" then
        config.set_sandbox_disabled(true)
        return M.response({enabled = false, message = "Sandbox disabled"})
    end
    return M.response(nil, ERR_INVALID_ARG, "Usage: sandbox [on|off|status|toggle]")
end

function SocketServer:_cmd_debug(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args == "" or args == "status" then
        return M.response({enabled = config.debug()})
    elseif args == "toggle" then
        local current = config.debug()
        config.set_debug(not current)
        return M.response({enabled = not current, message = "Debug " .. (not current and "enabled" or "disabled")})
    elseif args == "on" then
        config.set_debug(true)
        return M.response({enabled = true, message = "Debug enabled"})
    elseif args == "off" then
        config.set_debug(false)
        return M.response({enabled = false, message = "Debug disabled"})
    end
    return M.response(nil, ERR_INVALID_ARG, "Usage: debug [on|off|status|toggle]")
end

function SocketServer:_cmd_status(args)
    local messages = self.aicoder.message_history:get_messages()
    local is_proc = false
    if self.aicoder.session_manager then
        is_proc = self.aicoder.session_manager.is_processing
    elseif self.aicoder.is_processing ~= nil then
        is_proc = self.aicoder.is_processing
    end
    return M.response({
        processing = is_proc,
        yolo_enabled = config.yolo_mode(),
        detail_enabled = config.detail_mode(),
        sandbox_enabled = not config.sandbox_disabled(),
        debug_enabled = config.debug(),
        messages = #messages,
    })
end

function SocketServer:_cmd_stop(args)
    local stopped = false
    if self.aicoder.session_manager and self.aicoder.session_manager.is_processing then
        self.aicoder.session_manager.is_processing = false
        stopped = true
    elseif self.aicoder.is_processing then
        self.aicoder.is_processing = false
        stopped = true
    end
    if stopped then
        return M.response({stopped = true, message = "Processing stopped"})
    end
    return M.response(nil, ERR_NOT_PROCESSING, "Not currently processing")
end

function SocketServer:_cmd_messages(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local messages = self.aicoder.message_history:get_messages()
    if args == "count" then
        local n_user, n_assistant, n_system, n_tool = 0, 0, 0, 0
        for _, m in ipairs(messages) do
            if m.role == "user" then n_user = n_user + 1
            elseif m.role == "assistant" then n_assistant = n_assistant + 1
            elseif m.role == "system" then n_system = n_system + 1
            elseif m.role == "tool" then n_tool = n_tool + 1
            end
        end
        return M.response({
            total = #messages,
            user = n_user,
            assistant = n_assistant,
            system = n_system,
            tool = n_tool,
        })
    end
    return M.response({messages = messages, count = #messages})
end

function SocketServer:_cmd_inject(args)
    if not os.getenv("TMUX") then
        return M.response(nil, ERR_IO_ERROR, "This feature only works inside a tmux environment")
    end
    local editor = os.getenv("EDITOR") or "nano"
    local random_suffix = _gen_token_hex(4)
    local temp_path = temp_file.create_temp_file("aicoder-inject-" .. random_suffix, ".md")

    local f = io.open(temp_path, "w")
    if f then f:close() end

    local sync_point = "inject_done_" .. random_suffix
    local window_name = "inject_" .. random_suffix
    local tmux_cmd = string.format(
        'tmux new-window -n "%s" \'bash -c "%s %s; tmux wait-for -S %s"\'',
        window_name, editor, temp_path, sync_point)

    -- Spawn the editor
    os.execute(tmux_cmd .. " &")

    -- Wait and inject (we run this in a separate coroutine for non-blocking)
    local co = coroutine.create(function()
        os.execute("tmux wait-for " .. sync_point)
        local f2 = io.open(temp_path, "r")
        if f2 then
            local content = f2:read("*a"):gsub("^%s+", ""):gsub("%s+$", "")
            f2:close()
            if content ~= "" and self.aicoder.message_history.insert_user_message_at_appropriate_position then
                self.aicoder.message_history:insert_user_message_at_appropriate_position(content)
                if config.debug() then
                    log.debug("[Socket] Injected: " .. content:sub(1, 100))
                end
            end
        end
        os.remove(temp_path)
    end)
    coroutine.resume(co)

    return M.response({
        injected = false,
        message = "Editor opened. Message will be injected when you save and exit."
    })
end

function SocketServer:_cmd_inject_text(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args == "" then
        return M.response(nil, ERR_MISSING_ARG, "Missing base64 encoded text")
    end

    local decoded = b64decode(args)
    if not decoded or #decoded == 0 then
        return M.response(nil, ERR_INVALID_ARG, "Invalid base64 encoding")
    end

    if #decoded > MAX_INJECT_TEXT_SIZE then
        return M.response(nil, ERR_INVALID_ARG,
            "Text too large: " .. #decoded .. " bytes (max: " .. MAX_INJECT_TEXT_SIZE .. ")")
    end

    local ok, text = pcall(function() return decoded end)
    if not ok or type(text) ~= "string" then
        return M.response(nil, ERR_INVALID_ARG, "Invalid UTF-8 encoding")
    end

    if self.aicoder.message_history.insert_user_message_at_appropriate_position then
        self.aicoder.message_history:insert_user_message_at_appropriate_position(text)
    end

    if config.debug() then
        log.debug("[Socket] inject-text: " .. text:sub(1, 100))
    end

    return M.response({injected = true, length = #text})
end

function SocketServer:_cmd_command(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args == "" then
        return M.response(nil, ERR_MISSING_ARG, "Missing command")
    end
    if args:sub(1, 1) ~= "/" then
        return M.response(nil, ERR_INVALID_ARG, "Command must start with '/'")
    end

    if not (self.aicoder.command_handler and self.aicoder.command_handler.handle_command) then
        return M.response(nil, ERR_INTERNAL, "No command handler available")
    end

    local result = self.aicoder.command_handler:handle_command(args)

    if result.should_quit then
        self.aicoder.is_running = false
    end

    return M.response({
        executed = args,
        should_quit = result.should_quit,
        run_api_call = result.run_api_call,
    })
end

function SocketServer:_cmd_process(args)
    local is_proc = false
    if self.aicoder.session_manager and self.aicoder.session_manager.is_processing then
        is_proc = true
    elseif self.aicoder.is_processing then
        is_proc = true
    end
    if is_proc then
        return M.response(nil, ERR_NOT_PROCESSING, "Already processing, please wait")
    end

    -- Run processing in background
    if self.aicoder.session_manager and self.aicoder.session_manager.process_with_ai then
        local co = coroutine.create(function()
            local ok, err = pcall(function()
                self.aicoder.session_manager:process_with_ai()
            end)
            if not ok then
                log.error("[Socket] Process error: " .. tostring(err))
            end
        end)
        coroutine.resume(co)
    end

    if config.debug() then
        log.debug("[Socket] process: started AI processing in background")
    end
    return M.response({processing = true, message = "Started processing"})
end

function SocketServer:_cmd_save(args)
    local path = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then
        local save_dir = (os.getenv("PWD") or ".") .. "/.aicoder/sessions"
        os.execute("mkdir -p " .. save_dir)
        local ts = os.date("%Y-%m-%d_%H-%M-%S")
        path = save_dir .. "/session-" .. ts .. ".json"
    end

    -- Sandbox check
    local home = os.getenv("HOME") or ""
    local tmp_prefix = temp_file.get_temp_dir()
    if not (path:sub(1, #home) == home or path:sub(1, #tmp_prefix) == tmp_prefix) then
        return M.response(nil, ERR_PERMISSION, "Path outside allowed directories")
    end

    local messages = self.aicoder.message_history:get_messages()
    local f = io.open(path, "w")
    if not f then
        return M.response(nil, ERR_IO_ERROR, "Could not open " .. path)
    end
    f:write(json.encode({messages = messages}))
    f:close()
    log.info("Session saved to: " .. path)

    return M.response({saved = true, path = path})
end

function SocketServer:_cmd_kill(args)
    log.info("Killing AI Coder...")
    os.exit(137)
    return M.response({killed = true, message = "Terminating process"})
end

function SocketServer:_cmd_quit(args)
    log.info("Quitting AI Coder...")
    if self.aicoder.save_session then
        self.aicoder:save_session()
    end
    os.exit(143)
    return M.response({quit = true, message = "Shutting down"})
end

-- Stop the server
function SocketServer:stop()
    self.is_running = false
    if self.server_socket then
        pcall(function() self.server_socket:close() end)
        self.server_socket = nil
    end
    if self.socket_path then
        os.remove(self.socket_path)
    end
end

function SocketServer:get_socket_path()
    return self.socket_path
end

function SocketServer:get_status()
    return {
        is_running = self.is_running,
        socket_path = self.socket_path,
    }
end

function SocketServer:is_active()
    return self.is_running
end

-- Process any pending socket activity (call this from main loop)
function SocketServer:poll()
    self:_server_loop_step()
end

M.SocketServer = SocketServer
M.new = SocketServer.new

return M
