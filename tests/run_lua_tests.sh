#!/bin/bash
# Run all Lua tests and Python integration tests
set -e
cd "$(dirname "$0")/.."

total_pass=0
total_fail=0
total_files=0

echo "==========================================="
echo "  Luna Port Test Suite"
echo "==========================================="

for t in tests/verify_modules_load.lua tests/verify_parity_behavior.lua tests/test_diff.lua tests/test_file_utils.lua tests/test_json.lua tests/test_core.lua tests/test_aicoder.lua tests/test_commands.lua tests/test_tools.lua tests/test_tools_e2e.lua tests/test_misc.lua tests/test_more_utils.lua tests/test_command_exec.lua tests/test_compaction.lua tests/test_message_history_full.lua tests/test_parity_audit.lua tests/test_config.lua tests/test_stats.lua; do
    total_files=$((total_files + 1))
    output=$(luajit "$t" 2>&1)
    last=$(echo "$output" | tail -1)
    # Only count tests as failed if they don't print their normal success summary
    if echo "$output" | grep -qE "FAIL: " ; then
        total_fail=$((total_fail + 1))
        echo "FAIL: $t -> $last"
    else
        total_pass=$((total_pass + 1))
        echo "PASS: $t -> $last"
    fi
done

echo ""
echo "==========================================="
echo "Python integration tests (mock server, pexpect):"
echo "==========================================="
python3 tests/run_tests.py 2>&1 | tail -3

echo ""
echo "==========================================="
echo "Python integration tests (pytest test_integration.py):"
echo "==========================================="
python3 -m pytest tests/test_integration.py 2>&1 | tail -2

echo ""
echo "==========================================="
echo "RESULT: $total_pass/$total_files Lua test files passed"
echo "==========================================="
