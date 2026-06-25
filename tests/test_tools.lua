#!/usr/bin/env luajit
-- Lua unit tests for tools
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
print("\n=== Test: read_file tool ===")
local rf = require("tools.read_file")
check("read_file loads", type(rf) == "table")
check("TOOL_DEFINITION is table", type(rf.TOOL_DEFINITION) == "table")
check("read_file tool has execute", type(rf.execute) == "function")
check("formatArguments (module)", type(rf.formatArguments) == "function")
check("validateArguments (module)", type(rf.validateArguments) == "function")
check("formatArguments (nested)", type(rf.TOOL_DEFINITION.formatArguments) == "function")
check("validateArguments (nested)", type(rf.TOOL_DEFINITION.validateArguments) == "function")

-- ============================================================
print("\n=== Test: write_file tool ===")
local wf = require("tools.write_file")
check("write_file loads", type(wf) == "table")
check("TOOL_DEFINITION is table", type(wf.TOOL_DEFINITION) == "table")
check("formatArguments (module)", type(wf.formatArguments) == "function")
check("validateArguments (module)", type(wf.validateArguments) == "function")
check("_check_sandbox is function", type(wf._check_sandbox) == "function")
check("file_read is function", type(wf.file_read) == "function")

-- ============================================================
print("\n=== Test: edit_file tool ===")
local ef = require("tools.edit_file")
check("edit_file loads", type(ef) == "table")
check("TOOL_DEFINITION is table", type(ef.TOOL_DEFINITION) == "table")
-- module-level formatArguments/validateArguments/generatePreview inside TOOL_DEFINITION

-- ============================================================
print("\n=== Test: grep tool ===")
local gp = require("tools.grep")
check("grep loads", type(gp) == "table")
check("TOOL_DEFINITION is table", type(gp.TOOL_DEFINITION) == "table")
check("formatArguments (module)", type(gp.formatArguments) == "function")
check("validateArguments (module)", type(gp.validateArguments) == "function")
check("_check_sandbox is function", type(gp._check_sandbox) == "function")
check("_has_ripgrep is function", type(gp._has_ripgrep) == "function")

-- ============================================================
print("\n=== Test: list_directory tool ===")
local ld = require("tools.list_directory")
check("list_directory loads", type(ld) == "table")
check("TOOL_DEFINITION is table", type(ld.TOOL_DEFINITION) == "table")
check("formatArguments (module)", type(ld.formatArguments) == "function")
check("validateArguments (module)", type(ld.validateArguments) == "function")
check("_check_sandbox is function", type(ld._check_sandbox) == "function")
check("_list_single is function", type(ld._list_single) == "function")
check("_list_recursive is function", type(ld._list_recursive) == "function")
check("_walk is function", type(ld._walk) == "function")

-- ============================================================
print("\n=== Test: run_shell_command tool ===")
local rs = require("tools.run_shell_command")
check("run_shell_command loads", type(rs) == "table")
check("TOOL_DEFINITION is table", type(rs.TOOL_DEFINITION) == "table")
check("formatArguments (module)", type(rs.formatArguments) == "function")
check("validateArguments (module)", type(rs.validateArguments) == "function")
-- _kill_process_group not exposed at module level

-- ============================================================
print("\n=== Test: All 6 tools TOOL_DEFINITION has required fields ===")
local tool_files = {"read_file", "write_file", "edit_file", "grep", "list_directory", "run_shell_command"}
for _, name in ipairs(tool_files) do
    local tool = require("tools." .. name)
    local td = tool.TOOL_DEFINITION
    check(name .. ".TOOL_DEFINITION.description", type(td.description) == "string" and td.description ~= "")
    check(name .. ".TOOL_DEFINITION.parameters", type(td.parameters) == "table")
    check(name .. ".TOOL_DEFINITION.formatArguments", type(td.formatArguments) == "function")
    check(name .. ".TOOL_DEFINITION.validateArguments", type(td.validateArguments) == "function")
    check(name .. ".TOOL_DEFINITION.execute", type(td.execute) == "function")
    check(name .. ".TOOL_DEFINITION.type", type(td.type) == "string")
end

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
