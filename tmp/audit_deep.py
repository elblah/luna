#!/usr/bin/env python3
"""Deep audit: per-method coverage of Python vs Lua"""
import os
import re
import sys

PY_BASE = "/home/blah/poc/aicoder/v3/aicoder"
LUA_BASE = "/home/blah/poc/aicoder/luna"

def map_lua_path(py_rel):
    """Map Python file path to Lua file path"""
    p = py_rel.replace("tools/internal/", "tools/")
    return p[:-3] + ".lua"

def get_py_methods(path):
    """Extract all method names from a Python file (class methods + module-level)"""
    with open(path) as f:
        text = f.read()
    methods = {}
    # Module-level functions
    for m in re.finditer(r'^def (\w+)\(', text, re.M):
        name = m.group(1)
        if name.startswith('_') and name not in ('__init__',):
            continue
        if name in ('__init__', '__repr__', '__str__'):
            continue
        methods[name] = "module"
    # Class methods (any indent)
    for m in re.finditer(r'^    def (\w+)\(', text, re.M):
        name = m.group(1)
        if name.startswith('_') and name not in ('__init__',):
            continue
        if name in ('__init__', '__repr__', '__str__'):
            continue
        methods[name] = "class"
    # Static methods (decorated)
    for m in re.finditer(r'@staticmethod\s*\n\s*def (\w+)\(', text):
        name = m.group(1)
        if name.startswith('_'):
            continue
        methods[name] = "static"
    return methods

def get_lua_methods(path):
    """Extract all method names from a Lua file (any depth)"""
    with open(path) as f:
        text = f.read()
    methods = set()
    # M.foo = function or M:foo = function
    for m in re.finditer(r'M[:.](\w+)\s*=\s*function', text):
        methods.add(m.group(1))
    for m in re.finditer(r'M[:.](\w+)\s*=\s*', text):
        methods.add(m.group(1))
    # function M.foo / M:foo
    for m in re.finditer(r'function\s+M[:.](\w+)\s*\(', text):
        methods.add(m.group(1))
    # function self:foo
    for m in re.finditer(r'function\s+self[:.](\w+)\s*\(', text):
        methods.add(m.group(1))
    # local function foo
    for m in re.finditer(r'local\s+function\s+(\w+)\s*\(', text):
        methods.add(m.group(1))
    # ClassName:foo
    for m in re.finditer(r'function\s+\w+[:.](\w+)\s*\(', text):
        methods.add(m.group(1))
    # M.Foo = ...
    for m in re.finditer(r'M[:.](\w+)\s*=', text):
        methods.add(m.group(1))
    # TOOL_DEFINITION.X
    for m in re.finditer(r'TOOL_DEFINITION[:.](\w+)\s*=', text):
        methods.add(m.group(1))
    return methods

total_py = 0
total_lua = 0
total_missing = 0
files_with_missing = []
missing_details = {}

for root, dirs, files in os.walk(PY_BASE):
    for f in files:
        if not f.endswith('.py') or f.startswith('__'):
            continue
        py_path = os.path.join(root, f)
        rel = py_path[len(PY_BASE)+1:]
        lua_rel = map_lua_path(rel)
        lua_path = os.path.join(LUA_BASE, lua_rel)

        if not os.path.exists(lua_path):
            print(f"  MISSING FILE: {lua_rel}")
            continue

        py_methods = get_py_methods(py_path)
        lua_methods = get_lua_methods(lua_path)

        if not py_methods and not lua_methods:
            continue

        n_py = len(py_methods)
        n_lua = len(lua_methods)
        total_py += n_py
        total_lua += n_lua

        missing = []
        for name in py_methods:
            if name not in lua_methods:
                missing.append(name)
                total_missing += 1

        if missing:
            files_with_missing.append(rel)
            missing_details[rel] = missing
            print(f"  {rel}: {n_py} py / {n_lua} lua; MISSING: {missing}")

print(f"\n=== TOTALS ===")
print(f"  Python non-init methods: {total_py}")
print(f"  Lua methods/functions: {total_lua}")
print(f"  Missing in Lua: {total_missing}")
print(f"  Files with missing: {len(files_with_missing)}")

if total_missing == 0:
    print("  PASS: 100% method coverage")
    sys.exit(0)
else:
    sys.exit(1)
