#!/usr/bin/env luajit
-- Test that all Lua modules load without errors
local success = 0
local fail = 0
local failures = {}

local modules = {
    -- core
    "core.aicoder",
    "core.ai_processor",
    "core.anthropic_client",
    "core.command_handler",
    "core.compaction_service",
    "core.config",
    "core.context_bar",
    "core.file_access_tracker",
    "core.input_handler",
    "core.markdown_colorizer",
    "core.message_history",
    "core.plugin_system",
    "core.prompt_builder",
    "core.prompt_history",
    "core.session_manager",
    "core.socket_server",
    "core.stats",
    "core.token_estimator",
    "core.tool_executor",
    "core.tool_formatter",
    "core.tool_manager",
    -- commands
    "core.commands.base",
    "core.commands.compact",
    "core.commands.debug",
    "core.commands.detail",
    "core.commands.edit",
    "core.commands.help",
    "core.commands.load",
    "core.commands.edit_session",
    "core.commands.new",
    "core.commands.quit",
    "core.commands.registry",
    "core.commands.retry",
    "core.commands.sandbox",
    "core.commands.save",
    "core.commands.stats",
    "core.commands.thinking",
    "core.commands.yolo",
    -- utils
    "utils.datetime_utils",
    "utils.diff_utils",
    "utils.file_utils",
    "utils.http_utils",
    "utils.json_utils",
    "utils.jsonl_utils",
    "utils.log",
    "utils.path_utils",
    "utils.shell_utils",
    "utils.stdin_utils",
    "utils.temp_file_utils",
    -- tools
    "tools.edit_file",
    "tools.grep",
    "tools.list_directory",
    "tools.read_file",
    "tools.run_shell_command",
    "tools.write_file",
}

for _, mod in ipairs(modules) do
    local ok, err = pcall(require, mod)
    if ok then
        success = success + 1
    else
        fail = fail + 1
        table.insert(failures, mod .. ": " .. tostring(err))
    end
end

print(string.format("\n=== Module Load Test ==="))
print(string.format("Loaded: %d/%d", success, success + fail))

if fail > 0 then
    print("\nFAILURES:")
    for _, f in ipairs(failures) do
        print("  " .. f)
    end
    os.exit(1)
end

print("All modules load successfully")
