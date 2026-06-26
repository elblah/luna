# aicoder-lua

Pure Lua implementation of aicoder using LuaJIT + FFI.

## Quick Install

```bash
curl -fsSL https://github.com/elblah/luna/raw/main/install.sh | bash
```

Installs luajit, opt deps, adds `luna` alias to shell rc.

## Dependencies

### Required
- LuaJIT

### Optional (for performance)
On Debian/Ubuntu (system packages, auto-updated):
```bash
sudo apt install lua-cjson lua-filesystem lua-socket
```

On other platforms:
```bash
bash install.sh
```

- `lua-cjson` - Fast C-based JSON (falls back to built-in dkjson)
- `lua-filesystem` - Native filesystem ops (falls back to bash)
- `lua-socket` - Fast date/network ops (falls back to shell commands)

## Libraries used

| Library | Purpose | Location |
|---------|---------|-----------|
| LuaJIT FFI | Readline, libc calls | Built-in |
| dkjson | JSON encode/decode (pure Lua) | utils/dkjson.lua |
| cjson | JSON encode/decode (fast, optional) | lua-cjson |

## Architecture

- Pure Lua scripts (`*.lua`)
- LuaJIT FFI for C library bindings (readline, etc)
- Shell commands via `io.popen` or `c.spawn`

## Running

```bash
luajit main.lua
# Or with env:
API_KEY=xxx OPENAI_MODEL=xxx luajit main.lua
```

## Testing

```bash
bash tests/run_lua_tests.sh
```