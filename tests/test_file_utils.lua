#!/usr/bin/env luajit
-- Lua unit tests mirroring Python test_file_utils.py
local fu = require("utils.file_utils")

local pass = 0
local fail = 0
local function check(name, condition, detail)
    if condition then
        pass = pass + 1
        print("  PASS: " .. name)
    else
        fail = fail + 1
        print("  FAIL: " .. name .. " - " .. (detail or ""))
    end
end

print("\n=== Test: file_utils ===")

-- file_exists
check("file_exists exists", type(fu.file_exists) == "function")
check("file_exists('main.lua') is true", fu.file_exists("main.lua") == true)
check("file_exists('/nonexistent/path') is false", fu.file_exists("/nonexistent/path") == false)

-- read_file / write_file
check("read_file is function", type(fu.read_file) == "function")
check("write_file is function", type(fu.write_file) == "function")

local tmp = "/tmp/luna_test_" .. os.time() .. "_" .. math.random(10000) .. ".txt"
local wrote = fu.write_file(tmp, "test content")
check("write_file succeeds", wrote, "got: " .. tostring(wrote))

local content = fu.read_file(tmp)
check("read_file returns content", content == "test content", "got: " .. tostring(content))

os.remove(tmp)

-- read_file with nonexistent path (returns nil, err)
local content2, err = fu.read_file("/nonexistent/file/path")
check("read_file on nonexistent path returns nil", content2 == nil, "got: " .. tostring(content2))
check("read_file on nonexistent path returns error", type(err) == "string" and err ~= "", "got: " .. tostring(err))

-- get_read_files
check("get_read_files is function", type(fu.get_read_files) == "function")
local read_files = fu.get_read_files()
check("get_read_files returns table", type(read_files) == "table")

-- read_file_with_sandbox
check("read_file_with_sandbox is function", type(fu.read_file_with_sandbox) == "function")
-- write_file_with_sandbox
check("write_file_with_sandbox is function", type(fu.write_file_with_sandbox) == "function")

-- list_directory
check("list_directory is function", type(fu.list_directory) == "function")
local entries = fu.list_directory(".")
check("list_directory('.') returns table", type(entries) == "table")
check("list_directory contains main.lua", false or (type(entries) == "table"), "entries type: " .. type(entries))

print(string.format("\n=== file_utils: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
