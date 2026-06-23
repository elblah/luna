#!/usr/bin/env luajit
-- Lua unit tests mirroring Python test_diff_utils.py
local du = require("utils.diff_utils")
local config = require("core.config")

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

print("\n=== Test: diff_utils.colorize_diff ===")

-- Additions are green
local green = config.colors.green or "\x1b[32m"
local red = config.colors.red or "\x1b[31m"
local cyan = config.colors.cyan or "\x1b[36m"

local result = du.colorize_diff("+ This is an added line")
check("additions get green color", result:find(green, 1, true) ~= nil, "result: " .. result)

-- Deletions are red
result = du.colorize_diff("- This is a deleted line")
check("deletions get red color", result:find(red, 1, true) ~= nil, "result: " .. result)

-- Hunks are cyan
result = du.colorize_diff("@@ -1,3 +1,4 @@")
check("hunks get cyan color", result:find(cyan, 1, true) ~= nil, "result: " .. result)

-- Header lines (--- and +++) are NOT colored
result = du.colorize_diff("--- a/file.txt")
check("'---' header line not colored", result:find(green, 1, true) == nil and result:find(red, 1, true) == nil, "result: " .. result)

result = du.colorize_diff("+++ b/file.txt")
check("'+++' header line not colored", result:find(green, 1, true) == nil and result:find(red, 1, true) == nil, "result: " .. result)

-- Empty diff
result = du.colorize_diff("")
check("empty diff returns empty", result == "")

-- Multi-line diff
local multi = "line 1\n+ added\n- removed\nline 2"
result = du.colorize_diff(multi)
check("multi-line diff is processed", type(result) == "string" and #result > 0)

print(string.format("\n=== diff_utils: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
