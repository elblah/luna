-- JSON utilities
-- Ported from Python utils/json_utils.py

local M = {}

function M.write_file(path, data)
    local json = require("utils.json")
    local ok, content = pcall(json.encode, data)
    if not ok then
        return nil, "JSON encode failed: " .. tostring(content)
    end

    local f = io.open(path, "w")
    if not f then
        return nil, "Cannot open file for writing"
    end

    f:write(content)
    f:close()
    return true
end

function M.read_file(path, default_type)
    local json = require("utils.json")
    local f = io.open(path, "r")
    if not f then
        return nil
    end

    local content = f:read("*all")
    f:close()

    local ok, data = pcall(json.decode, content)
    if not ok then
        return nil
    end

    return data
end

function M.read_file_safe(path, default)
    local ok, data = pcall(function()
        return M.read_file(path)
    end)
    if not ok then
        return default
    end
    return data or default
end

function M.is_valid(json_string)
    if not json_string or #json_string == 0 then
        return false
    end

    local json = require("utils.json")
    local ok, _ = pcall(json.decode, json_string)
    return ok
end

function M.parse_safe(json_string, default)
    if not json_string or #json_string == 0 then
        return default
    end

    local json = require("utils.json")
    local ok, data = pcall(json.decode, json_string)
    if not ok then
        return default
    end
    return data
end

return M
