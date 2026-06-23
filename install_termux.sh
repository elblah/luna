#!/bin/bash
# install_termux.sh - Install optional performance dependencies on Termux
# Run: bash install_termux.sh

set -e

echo "=== Luna Termux Setup ==="

# Check if we're on Termux
if [ ! -d "/data/data/com.termux" ] && [ -z "$TERMUX_VERSION" ]; then
    echo "Warning: This script is designed for Termux. Continue anyway? (y/n)"
    read -r answer
    if [ "$answer" != "y" ]; then
        exit 1
    fi
fi

# Install luarocks if missing
if ! command -v luarocks &>/dev/null; then
    echo "[1/4] Installing luarocks..."
    pkg install -y luarocks
else
    echo "[1/4] luarocks already installed"
fi

# Find LuaJIT paths
echo "[2/4] Detecting LuaJIT paths..."

# Get LuaJIT version
LUAJIT_VERSION=$(luajit -v 2>&1 | grep -oP 'LuaJIT \K[0-9.]+')
echo "  LuaJIT version: $LUAJIT_VERSION"

# LuaRocks tree for LuaJIT
LUAROCKS_TREE="$HOME/.luarocks"
LUAJIT_LIB_PATH="$LUAROCKS_TREE/lib/lua/${LUAJIT_VERSION}"
LUAJIT_LUA_PATH="$LUAROCKS_TREE/share/lua/${LUAJIT_VERSION}"

echo "  luarocks tree: $LUAROCKS_TREE"
echo "  Lua path: $LUAJIT_LUA_PATH"
echo "  C lib path: $LUAJIT_LIB_PATH"

# Install packages for LuaJIT specifically
echo "[3/4] Installing packages..."

# lua-cjson
echo "  Installing lua-cjson..."
luarocks install --tree "$LUAROCKS_TREE" lua-cjson 2>/dev/null || \
luarocks install --tree "$LUAROCKS_TREE" lua-cjson-lj 2>/dev/null || \
echo "  Warning: cjson install failed, will use dkjson fallback"

# luafilesystem
echo "  Installing luafilesystem..."
luarocks install --tree "$LUAROCKS_TREE" luafilesystem 2>/dev/null || \
echo "  Warning: lfs install failed, will use bash fallback"

# luasocket
echo "  Installing luasocket..."
luarocks install --tree "$LUAROCKS_TREE" luasocket 2>/dev/null || \
echo "  Warning: luasocket install failed, will use shell fallback"

# Setup LUA_PATH in .bashrc
echo "[4/4] Configuring .bashrc..."

BASHRC="$HOME/.bashrc"
MARKER="# Luna LuaJIT paths"

if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    echo "  .bashrc already configured"
else
    echo "" >> "$BASHRC"
    echo "$MARKER" >> "$BASHRC"
    echo "export LUA_PATH=\"$LUAJIT_LUA_PATH/?.lua;$LUAJIT_LUA_PATH/?/init.lua;;\"" >> "$BASHRC"
    echo "export LUA_CPATH=\"$LUAJIT_LIB_PATH/?.so;;\"" >> "$BASHRC"
    echo "  Added LUA_PATH and LUA_CPATH to .bashrc"
fi

echo ""
echo "=== Setup complete ==="
echo "Run 'source ~/.bashrc' or restart terminal to apply changes."
echo ""
echo "Optional: Verify installation with:"
echo "  luajit -e \"print(require('cjson').encode({test=1}))\""
echo "  luajit -e \"print(require('lfs').currentdir())\""
