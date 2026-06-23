# Luna - AI Coder

Pure Lua AI coding assistant (LuaJIT).

Reference Python implementation: `$HOME/poc/aicoder/v3`

## Structure
- `main.lua` - Entry point
- `core/` - Core modules (ai_processor, command_handler, plugin_system, config, etc)
- `core/commands/` - Built-in slash commands (each is a separate module)
- `plugins/` - Plugin modules (shell, vision, snippets, empty_retry, etc)
- `tools/` - Tool implementations (read_file, edit_file, grep, etc)
- `utils/` - Utility modules (json, http, file, log, etc)
- `prompts/` - System prompts
- `tests/` - Test files (run with `lua tests/run_tests.sh`)

## Conventions
- Use `require("module.name")` for imports
- Commands inherit from `core/commands/base.lua`
- Plugins export `M:create_plugin(ctx)` function
- Register commands via `ctx:register_command(name, handler, description)`
- Register tools via `ctx:register_tool(name, fn, desc, params, auto_approved)`
- Config accessed via `require("core.config")` then `config.xxx()`
- Logging via `require("utils.log")` then `log.info/warn/error()`
- Color codes: `config.colors.green`, `.bold`, `.reset`, etc.

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
