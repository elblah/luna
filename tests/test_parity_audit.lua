#!/usr/bin/env luajit
-- Audit that catches alias-style methods too
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

local function get_py_methods(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local text = f:read("*a")
    f:close()
    local methods = {}
    -- match lines starting with 4 spaces then "def"
    for m in text:gmatch("\n    def (%w+)%(") do
        if m ~= "__init__" and m ~= "__repr__" and m ~= "__str__" then
            methods[m] = true
        end
    end
    -- also match top-level def (module-level functions)
    for m in text:gmatch("\ndef (%w+)%(") do
        if m ~= "__init__" and m ~= "__repr__" and m ~= "__str__" then
            methods[m] = true
        end
    end
    return methods
end

local function get_lua_methods(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local text = f:read("*a")
    f:close()
    local methods = {}
    -- function M:foo() or function M.foo()
    for m in text:gmatch("function%s+M[:.](%w+)%(") do methods[m] = true end
    -- function self:foo()
    for m in text:gmatch("function%s+self:(%w+)%(") do methods[m] = true end
    -- function FooClass:foo() or FooClass.foo()
    for m in text:gmatch("function%s+%w+[:.](%w+)%(") do methods[m] = true end
    -- M.foo = ... or M:foo = function ... (with possible leading whitespace)
    for m in text:gmatch("\n%s*M[:.](%w+)%s*=") do methods[m] = true end
    -- M.TOOL_DEFINITION.X = ... (TOOL_DEFINITION camelCase aliases)
    for m in text:gmatch("M%.TOOL_DEFINITION%.(%w+)%s*=") do methods[m] = true end
    for m in text:gmatch("TOOL_DEFINITION%.(%w+)%s*=") do methods[m] = true end
    -- local function foo
    for m in text:gmatch("local%s+function%s+(%w+)%(") do methods[m] = true end
    return methods
end

-- Map Python paths to Lua paths
local function map_path(rel)
    return rel:gsub("%.py$", ".lua"):gsub("tools/internal/", "tools/")
end

-- Run audit
print("\n=== Audit: Method coverage ===")
local total_py = 0
local total_lua = 0
local total_missing = 0
local missing_list = {}

local function audit_file(py_path)
    local rel = py_path:gsub("^/home/blah/poc/aicoder/v3/aicoder/", "")
    local lua_rel = map_path(rel)
    local lua_path = "/home/blah/poc/aicoder/luna/" .. lua_rel

    local lua_file = io.open(lua_path, "r")
    if not lua_file then return end
    lua_file:close()

    local py_methods = get_py_methods(py_path)
    local lua_methods = get_lua_methods(lua_path)

    for k in pairs(py_methods) do total_py = total_py + 1 end
    for k in pairs(lua_methods) do total_lua = total_lua + 1 end

    local missing = {}
    for k in pairs(py_methods) do
        if not lua_methods[k] then
            table.insert(missing, k)
            total_missing = total_missing + 1
        end
    end
    if #missing > 0 then
        missing_list[rel] = missing
    end
end

local f = io.popen("find /home/blah/poc/aicoder/v3/aicoder -name '*.py' -not -name '__*' | sort")
for line in f:lines() do
    if not line:find("__pycache__") then
        audit_file(line)
    end
end
f:close()

print(string.format("  Python methods (non-init): %d", total_py))
print(string.format("  Lua methods: %d", total_lua))
print(string.format("  Missing in Lua: %d", total_missing))
check("No missing methods", total_missing == 0,
    string.format("missing: %d", total_missing))

if total_missing > 0 then
    print("\nMissing methods by file:")
    for rel, missing in pairs(missing_list) do
        print(string.format("  %s: %s", rel, table.concat(missing, ", ")))
    end
end

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
