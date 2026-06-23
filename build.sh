#!/bin/bash
set -e

BIN_NAME="luna"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Luna Build Script ==="

# Check root/sudo access
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# Install luarocks if missing
if ! command -v luarocks &>/dev/null; then
    echo "[1/4] Installing luarocks..."
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq luarocks
else
    echo "[1/4] luarocks already installed"
fi

# Install luastatic if missing
if ! command -v luastatic &>/dev/null; then
    echo "[2/4] Installing luastatic..."
    luarocks install luastatic
else
    echo "[2/4] luastatic already installed"
fi

# Install LuaJIT dev headers if missing
if [ ! -f "/usr/include/luajit-2.1/lauxlib.h" ]; then
    echo "[3/4] Installing libluajit-5.1-dev..."
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq libluajit-5.1-dev
else
    echo "[3/4] LuaJIT dev headers already installed"
fi

# Build
echo "[4/4] Building $BIN_NAME..."
cd "$BUILD_DIR"

# Find all Lua source files
LUA_FILES=$(find core utils plugins tools -name '*.lua' 2>/dev/null | sort)
MAIN="main.lua"

if [ ! -f "$MAIN" ]; then
    echo "Error: $MAIN not found in $BUILD_DIR"
    exit 1
fi

luastatic $MAIN $LUA_FILES \
    -o "$BIN_NAME" \
    -lluajit-5.1 \
    -I/usr/include/luajit-2.1

# Clean up generated file
rm -f "$MAIN.luastatic.c"

echo ""
echo "=== Build complete: $BUILD_DIR/$BIN_NAME ==="
echo "Run: ./$BIN_NAME"
