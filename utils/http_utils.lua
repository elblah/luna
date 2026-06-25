-- HTTP utilities for Luna using curl (non-streaming only)

local json = require("utils.json")
local M = {}

-- Simple response object
local Response = {}
M.Response = Response
Response.__index = Response

function Response.new(status, headers, body)
    local self = setmetatable({}, Response)
    self.status = status or 0
    self.headers = headers or {}
    self.body = body or ""
    self.ok = status and status >= 200 and status < 300
    self.reason = ""
    return self
end

function Response:json()
    local ok, result = pcall(function()
        local json = require("utils.json")
        return json.decode(self.body)
    end)
    return ok and result or nil
end

function Response:read(n)
    if not self.body then return "" end
    if n then
        return self.body:sub(1, n)
    end
    return self.body
end

function Response:close()
    -- no-op
end

function Response:ok()
    return self.status and self.status >= 200 and self.status < 300
end

-- Simple fetch using curl (non-streaming)
function M.fetch(request_url, options)
    options = options or {}
    local method = options.method or "GET"
    local headers = options.headers or {}
    local body = options.body or ""
    local timeout = options.timeout or 30
    
    local curl_cmd = {"curl", "-s", "--compressed", "-X", method, "-H", '"User-Agent: Mozilla/5.0"'}
    
    for k, v in pairs(headers) do
        table.insert(curl_cmd, "-H")
        table.insert(curl_cmd, '"' .. k .. ": " .. v .. '"')
    end
    
    local tmp_file = nil
    if method == "POST" and body ~= "" then
        tmp_file = os.tmpname()
        local f = io.open(tmp_file, "w")
        if f then
            f:write(body)
            f:close()
            table.insert(curl_cmd, "-d")
            table.insert(curl_cmd, "@" .. tmp_file)
        else
            io.stderr:write("[http] ERROR: Cannot write temp file: " .. tostring(tmp_file) .. "\n")
            tmp_file = nil
        end
    end
    
    table.insert(curl_cmd, "-m")
    table.insert(curl_cmd, tostring(timeout))
    table.insert(curl_cmd, request_url)
    table.insert(curl_cmd, "2>/dev/null")
    
    local cmd_str = table.concat(curl_cmd, " ")
    
    -- Debug: print the actual curl command being executed
    if os.getenv("DEBUG") == "1" then
        io.stderr:write("[http] " .. cmd_str .. "\n")
        if tmp_file then
            local f = io.open(tmp_file, "r")
            if f then
                io.stderr:write("[http] Request body:\n" .. f:read("*a") .. "\n")
                f:close()
            end
        end
    end
    
    local handle = io.popen(cmd_str)
    if not handle then
        if tmp_file then os.remove(tmp_file) end
        return Response.new(0, {}, "Failed to execute curl")
    end
    
    local result = handle:read("*a")
    handle:close()
    
    -- Clean up temp file
    if tmp_file then os.remove(tmp_file) end
    
    local status = 200
    local error_msg = ""
    if result == "" or not result then
        status = 0
        error_msg = "Request cancelled or network error"
    elseif result:match('^%s*{"type":"error"') then
        -- Try to extract actual error from API response
        local ok, parsed = pcall(json.decode, result)
        if ok and parsed.error then
            error_msg = parsed.error.message or parsed.error.type or "Unknown API error"
        else
            error_msg = "API error"
        end
        status = 400  -- Bad request, not necessarily auth
    elseif not result:match('^%s*{') then
        status = 0
        error_msg = "Invalid response"
    end
    
    return Response.new(status, {}, result), error_msg
end

return M