#!/usr/bin/env luajit
-- Lua unit tests for json_utils, datetime_utils, http_utils
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
print("\n=== Test: json_utils ===")
local ju = require("utils.json_utils")
check("write_file is function", type(ju.write_file) == "function")
check("read_file is function", type(ju.read_file) == "function")
check("read_file_safe is function", type(ju.read_file_safe) == "function")
check("is_valid is function", type(ju.is_valid) == "function")
check("parse_safe is function", type(ju.parse_safe) == "function")

check("is_valid('{}') == true", ju.is_valid("{}") == true)
check("is_valid('[]') == true", ju.is_valid("[]") == true)
check("is_valid('null') == true", ju.is_valid("null") == true)
check("is_valid('123') == true", ju.is_valid("123") == true)
check("is_valid('{bad}') == false", ju.is_valid("{bad}") == false)
check("is_valid('') == false", ju.is_valid("") == false)
check("is_valid('not json') == false", ju.is_valid("not json") == false)

-- parse_safe returns default on invalid
check("parse_safe returns default on invalid", ju.parse_safe("not json", "default") == "default")
check("parse_safe returns default on nil", ju.parse_safe(nil, "def") == "def")
check("parse_safe returns parsed on valid", ju.parse_safe('{"a":1}', "def")["a"] == 1)

-- write_file + read_file roundtrip
local tmp = "/tmp/luna_json_test_" .. os.time() .. ".json"
local test_data = {name = "luna", version = "1.0.0", items = {1, 2, 3}}
ju.write_file(tmp, test_data)
local read_back = ju.read_file(tmp)
check("json roundtrip: name", read_back.name == "luna")
check("json roundtrip: version", read_back.version == "1.0.0")
check("json roundtrip: items[1]", read_back.items[1] == 1)
check("json roundtrip: items[3]", read_back.items[3] == 3)
os.remove(tmp)

-- read_file_safe with nonexistent
local safe = ju.read_file_safe("/nonexistent/path.json", "fallback")
check("read_file_safe returns default for missing", safe == "fallback")

-- ============================================================
print("\n=== Test: datetime_utils ===")
local dtu = require("utils.datetime_utils")
check("create_file_timestamp is function", type(dtu.create_file_timestamp) == "function")
check("create_timestamp_filename is function", type(dtu.create_timestamp_filename) == "function")
check("get_current_iso_datetime is function", type(dtu.get_current_iso_datetime) == "function")

local ts = dtu.create_file_timestamp()
check("create_file_timestamp returns string", type(ts) == "string" and #ts > 0)
local iso = dtu.get_current_iso_datetime()
check("get_current_iso_datetime returns string", type(iso) == "string" and #iso > 0)
check("get_current_iso_datetime contains T", iso:find("T") ~= nil)
check("get_current_iso_datetime contains -", iso:find("-", 1, true) ~= nil)
local fn = dtu.create_timestamp_filename("test", "log")
check("create_timestamp_filename with ext", fn:find("test") ~= nil and fn:find("log") ~= nil and fn:find(".", 1, true) ~= nil, "got: " .. fn)

-- ============================================================
print("\n=== Test: http_utils ===")
local hu = require("utils.http_utils")
check("fetch is function", type(hu.fetch) == "function")
check("Response is table", type(hu.Response) == "table")

local resp = hu.Response.new(200, {["content-type"] = "application/json"}, '{"ok":true}')
check("Response.new works", type(resp) == "table")
check("Response status == 200", resp.status == 200)
check("Response ok == true", resp.ok == true)
check("Response body has content", resp.body == '{"ok":true}')

local resp_404 = hu.Response.new(404, {}, "")
check("404 is not ok", resp_404.ok == false)

print(string.format("\n=== ALL: %d/%d passed ===", pass, pass + fail))
if fail > 0 then os.exit(1) end
