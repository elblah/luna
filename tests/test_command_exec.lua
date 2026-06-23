#!/usr/bin/env luajit
-- Lua unit tests for command execution
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
print("\n=== Test: help command ===")
local help = require("core.commands.help")
check("help loads", type(help) == "table")
check("new is function", type(help.new) == "function")
check("get_name is function", type(help.get_name) == "function" or type(help["get_name"]) == "function")
check("get_description is function", type(help.get_description) == "function")
check("get_aliases is function", type(help.get_aliases) == "function")
check("execute is function", type(help.execute) == "function")

-- Create a help instance
local ctx = {aicoder = {}}
local h = help.new(ctx)
check("help instance created", type(h) == "table")
check("help.get_name returns string", type(h:get_name()) == "string" and #h:get_name() > 0)
check("help.get_description returns string", type(h:get_description()) == "string")

-- Execute help
local result = h:execute({})
check("help execute returns CommandResult", type(result) == "table")

-- ============================================================
print("\n=== Test: stats command ===")
local stats_cmd = require("core.commands.stats")
check("stats cmd loads", type(stats_cmd) == "table")
check("new is function", type(stats_cmd.new) == "function")
check("get_name is function", type(stats_cmd.get_name) == "function" or type(stats_cmd["get_name"]) == "function")
check("get_description is function", type(stats_cmd.get_description) == "function")
check("get_aliases is function", type(stats_cmd.get_aliases) == "function")

-- ============================================================
print("\n=== Test: quit command ===")
local quit = require("core.commands.quit")
check("quit loads", type(quit) == "table")
check("new is function", type(quit.new) == "function")

-- ============================================================
print("\n=== Test: new command ===")
local new = require("core.commands.new")
check("new loads", type(new) == "table")
check("new is function", type(new.new) == "function")

-- ============================================================
print("\n=== Test: save command ===")
local save = require("core.commands.save")
check("save loads", type(save) == "table")
check("new is function", type(save.new) == "function")

-- ============================================================
print("\n=== Test: load command ===")
local load_cmd = require("core.commands.load")
check("load loads", type(load_cmd) == "table")
check("new is function", type(load_cmd.new) == "function")

-- ============================================================
print("\n=== Test: detail command ===")
local detail = require("core.commands.detail")
check("detail loads", type(detail) == "table")
check("new is function", type(detail.new) == "function")

-- ============================================================
print("\n=== Test: compact command ===")
local compact = require("core.commands.compact")
check("compact loads", type(compact) == "table")
check("new is function", type(compact.new) == "function")

-- ============================================================
print("\n=== Test: debug command ===")
local debug = require("core.commands.debug")
check("debug loads", type(debug) == "table")
check("new is function", type(debug.new) == "function")

-- ============================================================
print("\n=== Test: edit command ===")
local edit = require("core.commands.edit")
check("edit loads", type(edit) == "table")
check("new is function", type(edit.new) == "function")

-- ============================================================
print("\n=== Test: memory command ===")
local memory = require("core.commands.memory")
check("memory loads", type(memory) == "table")
check("new is function", type(memory.new) == "function")

-- ============================================================
print("\n=== Test: retry command ===")
local retry = require("core.commands.retry")
check("retry loads", type(retry) == "table")
check("new is function", type(retry.new) == "function")

-- ============================================================
print("\n=== Test: sandbox command ===")
local sandbox = require("core.commands.sandbox")
check("sandbox loads", type(sandbox) == "table")
check("new is function", type(sandbox.new) == "function")

-- ============================================================
print("\n=== Test: thinking command ===")
local thinking = require("core.commands.thinking")
check("thinking loads", type(thinking) == "table")
check("new is function", type(thinking.new) == "function")

-- ============================================================
print("\n=== Test: yolo command ===")
local yolo = require("core.commands.yolo")
check("yolo loads", type(yolo) == "table")
check("new is function", type(yolo.new) == "function")

-- ============================================================
print("\n=== Test: registry can list commands ===")
local reg = require("core.commands.registry")
local r = reg.new({aicoder = {}})
local cmds = r:get_all_commands()
local n_cmds = 0
if type(cmds) == "table" then
    for _ in pairs(cmds) do n_cmds = n_cmds + 1 end
end
check("registry has commands", n_cmds > 0, "found " .. n_cmds .. " commands")
print("    registered commands: " .. n_cmds)

-- Try to execute help via registry
if r.execute_command then
    local result = r:execute_command("/help")
    check("execute_command('/help') returns table", type(result) == "table",
        "got: " .. type(result))
end
if r.list_commands then
    local lc = r:list_commands()
    check("list_commands returns table", type(lc) == "table")
end

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
