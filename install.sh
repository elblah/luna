#!/bin/bash
# install.sh - Install optional performance dependencies
# Run: bash install.sh
# Supports: Termux, macOS (Homebrew), Linux (apt/apk/dnf/yum/pacman)

set -e

echo "=== Luna Setup ==="

# --- Platform detection ---
detect_platform() {
    if [ -d "/data/data/com.termux" ] || [ -n "$TERMUX_VERSION" ]; then
        OS="termux"
        PKG_MANAGER="pkg"
        SUDO=""
        PKG_UPDATE="pkg update"
        PKG_INSTALL="pkg install -y"
    elif [ "$(uname -s)" = "Darwin" ]; then
        OS="macos"
        PKG_MANAGER="brew"
        SUDO=""
        PKG_UPDATE="brew update"
        PKG_INSTALL="brew install"
    else
        OS="linux"
        if command -v apt &>/dev/null; then
            PKG_MANAGER="apt"
            SUDO="sudo"
            PKG_UPDATE="$SUDO apt-get update -qq"
            PKG_INSTALL="$SUDO apt-get install -y -qq"
        elif command -v apk &>/dev/null; then
            PKG_MANAGER="apk"
            SUDO="sudo"
            PKG_UPDATE="$SUDO apk update"
            PKG_INSTALL="$SUDO apk add"
        elif command -v dnf &>/dev/null; then
            PKG_MANAGER="dnf"
            SUDO="sudo"
            PKG_UPDATE="$SUDO dnf check-update || true"
            PKG_INSTALL="$SUDO dnf install -y"
        elif command -v yum &>/dev/null; then
            PKG_MANAGER="yum"
            SUDO="sudo"
            PKG_UPDATE="$SUDO yum check-update || true"
            PKG_INSTALL="$SUDO yum install -y"
        elif command -v pacman &>/dev/null; then
            PKG_MANAGER="pacman"
            SUDO="sudo"
            PKG_UPDATE="$SUDO pacman -Sy"
            PKG_INSTALL="$SUDO pacman -S --noconfirm"
        else
            echo "Error: unsupported package manager (tried apt/apk/dnf/yum/pacman)"
            exit 1
        fi
    fi
    echo "  Platform: $OS ($PKG_MANAGER)"
}

detect_platform

# --- Install dependencies ---
echo "[1/3] Installing dependencies..."

# Always need luajit
if ! command -v luajit &>/dev/null; then
    echo "  Installing luajit..."
    $PKG_UPDATE
    $PKG_INSTALL luajit
    if ! command -v luajit &>/dev/null; then
        echo "  Error: luajit install failed. Install manually."
        exit 1
    fi
else
    echo "  luajit already installed"
fi

# Lua packages: prefer system packages on Debian (auto-updated)
# On Termux/macOS/others, use luarocks
if [ "$OS" = "linux" ] && [ "$PKG_MANAGER" = "apt" ]; then
    echo "  Installing lua packages via apt (system packages)..."
    $PKG_INSTALL lua-cjson lua-filesystem lua-socket 2>/dev/null || \
        echo "  Warning: some system lua packages unavailable, falling back to luarocks"
    # Still install luarocks if some packages failed
    if ! command -v luarocks &>/dev/null; then
        $PKG_INSTALL luarocks 2>/dev/null || true
    fi
else
    if ! command -v luarocks &>/dev/null; then
        echo "  Installing luarocks..."
        $PKG_UPDATE
        $PKG_INSTALL luarocks
    else
        echo "  luarocks already installed"
    fi
fi

# --- Install LuaRocks packages (if luarocks available) ---
if command -v luarocks &>/dev/null; then
    echo "[2/3] Installing LuaRocks packages..."

    LUAJIT_VERSION=$(luajit -v 2>&1 | grep -oP 'LuaJIT \K[0-9.]+' || echo "5.1")
    LUAROCKS_TREE="$HOME/.luarocks"

    echo "  Installing lua-cjson..."
    luarocks install --tree "$LUAROCKS_TREE" lua-cjson 2>/dev/null || \
    luarocks install --tree "$LUAROCKS_TREE" lua-cjson-lj 2>/dev/null || \
    echo "  Warning: cjson install failed, will use dkjson fallback"

    echo "  Installing luafilesystem..."
    luarocks install --tree "$LUAROCKS_TREE" luafilesystem 2>/dev/null || \
    echo "  Warning: lfs install failed, will use shell fallback"

    echo "  Installing luasocket..."
    luarocks install --tree "$LUAROCKS_TREE" luasocket 2>/dev/null || \
    echo "  Warning: luasocket install failed, will use shell fallback"
fi

# --- Determine shell rc file ---
RCFILE="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
    RCFILE="$HOME/.zshrc"
elif [ -f "$HOME/.bash_profile" ]; then
    RCFILE="$HOME/.bash_profile"
elif [ -f "$HOME/.profile" ]; then
    RCFILE="$HOME/.profile"
fi

# --- Add luna alias ---
echo "[3/3] Adding luna alias..."

# On non-apt systems using luarocks, set LUA_PATH to find installed rocks
if command -v luarocks &>/dev/null && [ "$PKG_MANAGER" != "apt" ]; then
    LUAJIT_VERSION=$(luajit -v 2>&1 | grep -oP 'LuaJIT \K[0-9.]+' || echo "5.1")
    LUAROCKS_TREE="$HOME/.luarocks"
    LUAJIT_LUA_PATH_VAL="$LUAROCKS_TREE/share/lua/${LUAJIT_VERSION}"
    LUAJIT_LIB_PATH_VAL="$LUAROCKS_TREE/lib/lua/${LUAJIT_VERSION}"
fi

LUNA_DIR="$(cd "$(dirname "$0")" && pwd)"
ALIAS_MARKER="# Luna alias"

if grep -q "$ALIAS_MARKER" "$RCFILE" 2>/dev/null; then
    echo "  luna alias already configured"
else
    echo "" >> "$RCFILE"
    echo "$ALIAS_MARKER" >> "$RCFILE"
    echo "alias luna='luajit \"$LUNA_DIR/main.lua\"'" >> "$RCFILE"
    echo "  Added alias: luna='luajit $LUNA_DIR/main.lua'"
fi

echo ""
echo "=== Setup complete ==="
echo "Run 'source $RCFILE' or restart terminal to apply changes."
echo ""
echo "Usage: luna"
echo ""
echo "Optional: Verify installation with:"
echo "  luajit -e \"print(require('cjson').encode({test=1}))\""
echo "  luajit -e \"print(require('lfs').currentdir())\""
