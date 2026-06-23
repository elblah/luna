#!/usr/bin/env luajit
-- Lua unit tests for remaining utils: jsonl, path, shell, stdin, stream, temp_file, log
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

-- ============================================================
print("\n=== Test: jsonl_utils ===")
local jlu = require("utils.jsonl_utils")
check("jsonl_utils loads", type(jlu) == "table")
local jlu_methods = {}
for k in pairs(jlu) do table.insert(jlu_methods, k) end
print("    methods: " .. table.concat(jlu_methods, ", "))

-- write_file + read_file roundtrip
local tmp_jsonl = "/tmp/luna_jsonl_test_" .. os.time() .. ".jsonl"
local entries = {{a = 1, b = 2}, {a = 3, b = 4}}
if jlu.write_file then
    jlu.write_file(tmp_jsonl, entries)
    local read_back = jlu.read_file(tmp_jsonl)
    check("jsonl roundtrip returns list", type(read_back) == "table" and #read_back == 2)
    check("jsonl entry 1 matches", read_back[1] and read_back[1].a == 1)
    os.remove(tmp_jsonl)
end

-- ============================================================
print("\n=== Test: path_utils ===")
local pu = require("utils.path_utils")
check("path_utils loads", type(pu) == "table")
local pu_methods = {}
for k in pairs(pu) do table.insert(pu_methods, k) end
print("    methods: " .. table.concat(pu_methods, ", "))

-- Test some path functions
if pu.normalize_path then
    local n = pu.normalize_path("./foo/../bar")
    check("normalize_path returns string", type(n) == "string" and #n > 0, "got: " .. tostring(n))
end
if pu.is_within_sandbox then
    local inside = pu.is_within_sandbox(".", ".")
    check("is_within_sandbox returns boolean", type(inside) == "boolean")
end

-- ============================================================
print("\n=== Test: shell_utils ===")
local su = require("utils.shell_utils")
check("shell_utils loads", type(su) == "table")
local su_methods = {}
for k in pairs(su) do table.insert(su_methods, k) end
print("    methods: " .. table.concat(su_methods, ", "))

if su.ShellResult then
    -- signature: ShellResult.new(success, exit_code, stdout, stderr)
    local sr = su.ShellResult.new(true, 0, "out", "err")
    check("ShellResult.new is function", type(su.ShellResult.new) == "function")
    if sr then
        check("ShellResult has success", sr.success == true)
        check("ShellResult has exit_code", sr.exit_code == 0)
        check("ShellResult has stdout", sr.stdout == "out")
        check("ShellResult has stderr", sr.stderr == "err")
    end
end

-- Execute real command
if su.execute_command_sync then
    local result = su.execute_command_sync("echo hello")
    check("execute_command_sync returns ShellResult", type(result) == "table")
    check("execute_command_sync stdout has hello", result.stdout and result.stdout:find("hello", 1, true) ~= nil,
        "stdout: " .. tostring(result.stdout))
end

if su.is_executable then
    local ok = su.is_executable("echo")
    check("is_executable('echo') returns true", ok == true)
    local notok = su.is_executable("nonexistent_xyz_12345")
    check("is_executable('nonexistent') returns false", notok == false)
end

-- ============================================================
print("\n=== Test: stdin_utils ===")
local stu = require("utils.stdin_utils")
check("stdin_utils loads", type(stu) == "table")
local stu_methods = {}
for k in pairs(stu) do table.insert(stu_methods, k) end
print("    methods: " .. table.concat(stu_methods, ", "))

if stu.read_stdin_as_string then
    -- Can't easily test interactive stdin, but function should exist
    check("read_stdin_as_string is function", type(stu.read_stdin_as_string) == "function")
end
if stu.is_stdin_interactive then
    local interactive = stu.is_stdin_interactive()
    check("is_stdin_interactive returns boolean", type(interactive) == "boolean")
end

-- ============================================================
print("\n=== Test: stream_utils ===")
local strmu = require("utils.stream_utils")
check("stream_utils loads", type(strmu) == "table")
local strm_methods = {}
for k in pairs(strmu) do table.insert(strm_methods, k) end
print("    methods: " .. table.concat(strm_methods, ", "))

-- Test parse_sse_line if it exists
if strmu.parse_sse_line then
    local data = strmu.parse_sse_line("data: {\"hello\":\"world\"}")
    check("parse_sse_line returns data", type(data) == "string" or type(data) == "table",
        "got: " .. tostring(data))
end

-- ============================================================
print("\n=== Test: temp_file_utils ===")
local tfu = require("utils.temp_file_utils")
check("temp_file_utils loads", type(tfu) == "table")
local tfu_methods = {}
for k in pairs(tfu) do table.insert(tfu_methods, k) end
print("    methods: " .. table.concat(tfu_methods, ", "))

-- Functional tests
local tmpdir = tfu.get_temp_dir and tfu.get_temp_dir()
check("get_temp_dir returns string", type(tmpdir) == "string" and #tmpdir > 0,
    "got: " .. tostring(tmpdir))

local tmpfile, err = tfu.create_temp_file("luna_test_", ".txt")
if tmpfile then
    check("create_temp_file returns path", type(tmpfile) == "string")
    -- Write content
    if tfu.write_temp_file then
        tfu.write_temp_file(tmpfile, "test content")
        -- Read back
        local f = io.open(tmpfile, "r")
        if f then
            local content = f:read("*a")
            f:close()
            check("temp file content matches", content == "test content",
                "got: " .. tostring(content))
        end
    end
    -- Cleanup
    if tfu.delete_file then
        tfu.delete_file(tmpfile)
        check("delete_file removes file", not (tfu.get_temp_dir and io.open(tmpfile, "r")))
    end
end

-- ============================================================
print("\n=== Test: log ===")
local log = require("utils.log")
check("log loads", type(log) == "table")
check("LogUtils alias", type(log.LogUtils) == "table")
check("LogOptions alias", type(log.LogOptions) == "table")

local lo = log.LogOptions
print("    LogOptions: " .. tostring(lo))

-- Common log functions
for _, name in ipairs({"debug", "info", "warning", "error", "exception", "log"}) do
    if log[name] then
        check("log." .. name .. " is function", type(log[name]) == "function")
    end
end

-- Run a log function to ensure no crash
if log.info then
    log.info("test message from test_more_utils")
    check("log.info runs without error", true)
end
if log.error then
    log.error("test error from test_more_utils")
    check("log.error runs without error", true)
end

-- ============================================================
print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
