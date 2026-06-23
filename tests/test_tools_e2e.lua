#!/usr/bin/env luajit
-- Functional end-to-end tests for tools
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
print("\n=== Test: read_file.execute ===")
local rf = require("tools.read_file")
local tmpfile = "/tmp/luna_tool_test_" .. os.time() .. ".txt"
local fu = require("utils.file_utils")
fu.write_file(tmpfile, "line 1\nline 2\nline 3\nline 4\nline 5\n")
local res = rf.execute({path = tmpfile})
check("read_file returns table", type(res) == "table", "got: " .. type(res))
check("read_file has tool field", res.tool == "read_file")
check("read_file has detailed content", res.detailed and res.detailed:find("line 1", 1, true) ~= nil,
    "detailed: " .. tostring(res.detailed))
os.remove(tmpfile)

-- offset/limit (offset=0 = whole file, limit=N caps the lines)
fu.write_file(tmpfile, "a\nb\nc\nd\ne\n")
res = rf.execute({path = tmpfile, offset = 0, limit = 3})
check("read_file with limit=3", type(res) == "table" and res.detailed ~= nil)
check("read_file with limit has 3 lines", res.detailed:find("a", 1, true) and res.detailed:find("b", 1, true) and res.detailed:find("c", 1, true))
os.remove(tmpfile)

-- ============================================================
print("\n=== Test: write_file.execute ===")
local wf = require("tools.write_file")
local wf_test = "/tmp/luna_wf_test_" .. os.time() .. ".txt"
local res2 = wf.execute({path = wf_test, content = "hello world"})
check("write_file returns table", type(res2) == "table", "got: " .. type(res2))
check("write_file created file", fu.file_exists(wf_test))
check("write_file content matches", fu.read_file(wf_test) == "hello world")
os.remove(wf_test)

-- ============================================================
print("\n=== Test: grep.execute ===")
local gp = require("tools.grep")
-- Create a temp file to grep
local grep_test = "/tmp/luna_grep_test_" .. os.time() .. ".txt"
fu.write_file(grep_test, "alpha\nbeta\ngamma\nalpha again\n")
-- grep needs 'text' parameter
local res3 = gp.execute({text = "alpha", path = "/tmp/luna_grep_test_*.txt"})
check("grep returns table", type(res3) == "table", "got: " .. type(res3))
check("grep output contains 'alpha'", res3.detailed and res3.detailed:find("alpha", 1, true) ~= nil,
    "detailed: " .. tostring(res3.detailed))
os.remove(grep_test)

-- ============================================================
print("\n=== Test: list_directory.execute ===")
local ld = require("tools.list_directory")
local res4 = ld.execute({path = "."})
check("list_directory returns table", type(res4) == "table", "got: " .. type(res4))
check("list_directory has tool field", res4.tool == "list_directory")
check("list_directory detailed is non-empty", res4.detailed and #res4.detailed > 0)
-- Either contains entries OR is empty (we have many files in luna)
local has_entries = res4.detailed and res4.detailed:find("tests", 1, true) ~= nil
local is_empty = res4.friendly and res4.friendly:find("empty", 1, true) ~= nil
check("list_directory output has entries or is empty", has_entries or is_empty, "detailed: " .. tostring(res4.detailed))

-- ============================================================
print("\n=== Test: run_shell_command.execute ===")
local rs = require("tools.run_shell_command")
local res5 = rs.execute({command = "echo hello"})
check("run_shell_command echo returns table", type(res5) == "table", "got: " .. type(res5))
check("run_shell_command echo output", res5.detailed and res5.detailed:find("hello", 1, true) ~= nil,
    "detailed: " .. tostring(res5.detailed))

-- failure case (use a non-existent command, which has clearer error)
local res6 = rs.execute({command = "this_command_does_not_exist_xyz123"})
check("run_shell_command invalid returns table", type(res6) == "table")
check("run_shell_command invalid has output", res6.detailed ~= nil, "detailed: " .. tostring(res6.detailed))

-- ============================================================
print("\n=== Test: edit_file.execute ===")
local ef = require("tools.edit_file")
local edit_test = "/tmp/luna_edit_test_" .. os.time() .. ".txt"
fu.write_file(edit_test, "hello world\nfoo bar\n")
-- Must record the file as read first (sandbox check)
ef.record_read(edit_test)
local res7 = ef.execute({path = edit_test, old_string = "hello world", new_string = "hi world"})
check("edit_file returns table", type(res7) == "table", "got: " .. type(res7))
check("edit_file modified content", fu.read_file(edit_test) == "hi world\nfoo bar\n",
    "content: " .. fu.read_file(edit_test))
os.remove(edit_test)

-- invalid edit (string not found) — needs read first
local edit_test2 = "/tmp/luna_edit_test2_" .. os.time() .. ".txt"
fu.write_file(edit_test2, "hello\n")
ef.record_read(edit_test2)
local res8 = ef.execute({path = edit_test2, old_string = "not found", new_string = "x"})
check("edit_file with missing string returns table", type(res8) == "table")
-- Should indicate failure in friendly message
check("edit_file missing string has error",
    res8.friendly and (res8.friendly:lower():find("not found") ~= nil or res8.friendly:lower():find("error") ~= nil),
    "friendly: " .. tostring(res8.friendly))
os.remove(edit_test2)

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
