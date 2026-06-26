#!/bin/bash
# install.sh - Install luna
#   bash install.sh          # from repo checkout
#   curl -fsSL https://github.com/elblah/luna/raw/main/install.sh | bash
set -e

# If not in repo, clone and re-run
if [ ! -f main.lua ]; then
    INSTALL_DIR="${LUNA_INSTALL_DIR:-$HOME/.local/share/luna}"
    echo "=== Luna Installer ==="
    echo "Target: $INSTALL_DIR"
    git clone https://github.com/elblah/luna.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    exec bash install.sh
fi

LUNA_DIR="$(cd "$(dirname "$0")" && pwd -P)"
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

# System packages on Debian (auto-updated); luarocks on others
if [ "$OS" = "linux" ] && [ "$PKG_MANAGER" = "apt" ]; then
    echo "  Installing lua packages via apt..."
    $PKG_INSTALL lua-cjson lua-filesystem lua-socket 2>/dev/null || \
        echo "  Warning: some system lua packages unavailable"
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

# --- LuaRocks packages ---
if command -v luarocks &>/dev/null; then
    echo "[2/3] Installing LuaRocks packages..."
    LUAROCKS_TREE="$HOME/.luarocks"

    echo "  Installing lua-cjson..."
    luarocks install --tree "$LUAROCKS_TREE" lua-cjson 2>/dev/null || \
    luarocks install --tree "$LUAROCKS_TREE" lua-cjson-lj 2>/dev/null || \
    echo "  Warning: cjson install failed, dkjson fallback used"

    echo "  Installing luafilesystem..."
    luarocks install --tree "$LUAROCKS_TREE" luafilesystem 2>/dev/null || \
    echo "  Warning: lfs install failed, shell fallback used"

    echo "  Installing luasocket..."
    luarocks install --tree "$LUAROCKS_TREE" luasocket 2>/dev/null || \
    echo "  Warning: luasocket install failed, shell fallback used"
fi

# --- Shell rc file ---
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
echo "Run 'source $RCFILE' or restart terminal."
echo ""
echo "Usage: luna"
