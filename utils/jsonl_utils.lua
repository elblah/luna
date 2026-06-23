-- JSONL utilities
-- Ported from Python utils/jsonl_utils.py

local M = {}

function M.write_file(path, data)
    local json = require("utils.json")
    local lines = {}
    for _, item in ipairs(data) do
        local ok, line = pcall(json.encode, item)
        if ok then
            table.insert(lines, line)
        end
    end

    local f = io.open(path, "w")
    if not f then
        return false, "Cannot open file for writing"
    end

    f:write(table.concat(lines, "\n"))
    f:close()
    return true
end

function M.read_file(path)
    local json = require("utils.json")
    local f = io.open(path, "r")
    if not f then
        return nil
    end

    local content = f:read("*all")
    f:close()

    local results = {}
    for line in content:gmatch("[^\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line and #line > 0 then
            local ok, item = pcall(json.decode, line)
            if ok then
                table.insert(results, item)
            end
        end
    end

    return results
end

return M
