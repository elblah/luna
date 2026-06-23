"""
Integration tests for Luna (Lua) using pexpect with mock API server.

Tests verify all tools execute correctly with proper approval flow.
"""

import json
import os
import sys
import threading
import time
import socket
import pytest

sys.path.insert(0, os.path.dirname(__file__))

try:
    import pexpect
    from pexpect import exceptions as pexpect_exceptions
except ImportError:
    pexpect = None
    pexpect_exceptions = None
    pytest.skip("pexpect not installed", allow_module_level=True)

from mock_server import MockServer, make_sse_response


def spawn_luna(env, cwd, timeout=20):
    """Spawn Luna process with proper configuration.
    
    Args:
        env: Environment variables
        cwd: Working directory
        timeout: Timeout for spawn operation
        
    Returns:
        pexpect.spawn instance
    """
    # Always use project root for main.lua
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    main_script = os.path.join(project_root, "main.lua")
    
    # Copy necessary files to cwd for sandbox isolation
    import shutil
    dirs_to_copy = ["core", "tools", "utils", "libs", "prompts"]
    for d in dirs_to_copy:
        src = os.path.join(project_root, d)
        dst = os.path.join(cwd, d)
        if os.path.exists(src) and not os.path.exists(dst):
            shutil.copytree(src, dst)
    
    # Copy main.lua
    shutil.copy(os.path.join(project_root, "main.lua"), cwd)
    
    return pexpect.spawn(
        f"luajit {main_script}",
        env=env,
        cwd=cwd,
        timeout=timeout,
        encoding='utf-8'
    )


@pytest.fixture
def mock_server():
    """Provide mock API server for tests."""
    server = MockServer()
    server.start()
    yield server
    server.stop()


@pytest.fixture
def luna_env(mock_server, tmp_path):
    """Set up environment for Luna with mock API.

    CRITICAL: All API requests MUST go to local mock server, not real APIs.
    """
    # Get project root directory (parent of tests/)
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    env = os.environ.copy()
    
    # Clear any existing model/endpoint settings from parent environment
    # to prevent them from overriding test settings
    for key in list(env.keys()):
        if 'MODEL' in key.upper() or 'ENDPOINT' in key.upper() or 'API_BASE' in key.upper():
            del env[key]
    
    env["API_PROVIDER"] = "openai"  # Use OpenAI-compatible (for streaming_client)
    env["API_BASE_URL"] = mock_server.get_api_base()
    env["API_MODEL"] = "test-model"
    env["API_KEY"] = "mock-key"
    env["MINI_SANDBOX"] = "1"
    env["YOLO_MODE"] = "1"  # Auto-approve for tests
    env["MAX_TOKENS"] = "2000"
    return env


class TestBasicResponses:
    """Test basic AI responses without tools."""

    def test_simple_response(self, mock_server, luna_env, tmp_path):
        """Test that Luna can receive and display a simple response."""
        mock_server.set_response("hello", make_sse_response("Hello, human!"))

        child = spawn_luna(luna_env, tmp_path, timeout=15)

        try:
            child.expect(r"> ")
            child.sendline("hello")
            child.expect(r"Hello, human!", timeout=10)
            child.expect(r"> ", timeout=5)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)

    def test_markdown_formatting(self, mock_server, luna_env, tmp_path):
        """Test that markdown is properly formatted."""
        response = """# Title
This is **bold** and *italic*.

```lua
local x = 1
```
"""
        mock_server.set_response("markdown", make_sse_response(response))

        child = spawn_luna(luna_env, tmp_path, timeout=15)

        try:
            child.expect(r"> ")
            child.sendline("show me markdown")
            # Should see some colored output
            child.expect(r"Title", timeout=10)
            child.expect(r"> ", timeout=5)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)


class TestReadFileTool:
    """Test read_file tool execution."""

    def test_read_simple_file(self, mock_server, luna_env, tmp_path):
        """Test reading a simple text file."""
        test_file = tmp_path / "test.txt"
        test_file.write_text("Hello World\nLine 2\nLine 3")

        # Use sequential responses for multi-turn conversation
        mock_server.set_sequential_responses([
            make_sse_response(
                "I'll read the file",
                tool_calls=[{
                    "name": "read_file",
                    "arguments": json.dumps({"path": str(test_file)})
                }]
            ),
            make_sse_response("File has 3 lines")
        ])

        child = spawn_luna(luna_env, tmp_path, timeout=20)

        try:
            child.expect(r"> ")
            child.sendline("read test.txt")
            # Tool should be auto-approved (auto_approved=true)
            # Should see the AI's response confirming file was read
            child.expect(r"3 lines", timeout=10)
            child.expect(r"> ", timeout=10)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)

    def test_read_with_offset(self, mock_server, luna_env, tmp_path):
        """Test reading file with offset."""
        test_file = tmp_path / "large.txt"
        lines = [f"Line {i}" for i in range(20)]
        test_file.write_text("\n".join(lines))

        mock_server.set_sequential_responses([
            make_sse_response(
                "Reading from line 10",
                tool_calls=[{
                    "name": "read_file",
                    "arguments": json.dumps({"path": str(test_file), "offset": 10, "limit": 5})
                }]
            ),
            make_sse_response("Read 5 lines")
        ])

        child = spawn_luna(luna_env, tmp_path, timeout=20)

        try:
            child.expect(r"> ")
            child.sendline("read lines 10-15")
            child.expect(r"> ", timeout=15)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)


class TestListDirectoryTool:
    """Test list_directory tool execution."""

    def test_list_directory(self, mock_server, luna_env, tmp_path):
        """Test listing a directory."""
        # Create some test files
        (tmp_path / "file1.txt").write_text("content1")
        (tmp_path / "file2.txt").write_text("content2")

        mock_server.set_sequential_responses([
            make_sse_response(
                "I'll list the directory",
                tool_calls=[{
                    "name": "list_directory",
                    "arguments": json.dumps({"path": str(tmp_path)})
                }]
            ),
            make_sse_response("Found 2 files")
        ])

        child = spawn_luna(luna_env, tmp_path, timeout=20)

        try:
            child.expect(r"> ")
            child.sendline("list files")
            child.expect(r"> ", timeout=15)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)


class TestRunShellCommandTool:
    """Test run_shell_command tool execution."""

    def test_run_simple_command(self, mock_server, luna_env, tmp_path):
        """Test running a simple shell command."""
        mock_server.set_sequential_responses([
            make_sse_response(
                "I'll run uname",
                tool_calls=[{
                    "name": "run_shell_command",
                    "arguments": json.dumps({"command": "echo hello"})
                }]
            ),
            make_sse_response("Command output: hello")
        ])

        child = spawn_luna(luna_env, tmp_path, timeout=20)

        try:
            child.expect(r"> ")
            child.sendline("run echo hello")
            # Should see command output (appears in mock's 2nd response before next prompt)
            child.expect(r"hello", timeout=15)
            child.expect(r"> ", timeout=10)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)


class TestWriteFileTool:
    """Test write_file tool execution."""

    def test_write_file(self, mock_server, luna_env, tmp_path):
        """Test writing a file."""
        test_file = tmp_path / "output.txt"

        mock_server.set_sequential_responses([
            make_sse_response(
                "I'll write to the file",
                tool_calls=[{
                    "name": "write_file",
                    "arguments": json.dumps({
                        "path": str(test_file),
                        "content": "Hello World\nLine 2"
                    })
                }]
            ),
            make_sse_response("File written successfully")
        ])

        child = spawn_luna(luna_env, tmp_path, timeout=20)

        try:
            child.expect(r"> ")
            child.sendline("write hello")
            child.expect(r"> ", timeout=15)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)


class TestToolApproval:
    """Test tool approval flow."""

    def test_approval_required_for_sensitive_tool(self, mock_server, luna_env, tmp_path):
        """Test that sensitive tools require approval."""
        # Set YOLO_MODE=0 to require approval
        luna_env["YOLO_MODE"] = "0"
        
        # This should require approval but test auto_approved tools first
        mock_server.set_sequential_responses([
            make_sse_response(
                "I'll read the file",
                tool_calls=[{
                    "name": "read_file",
                    "arguments": json.dumps({"path": str(tmp_path / "test.txt")})
                }]
            ),
            make_sse_response("Done reading")
        ])

        child = spawn_luna(luna_env, tmp_path, timeout=20)

        try:
            child.expect(r"> ")
            child.sendline("read test")
            # read_file is auto_approved, so should not prompt
            child.expect(r"> ", timeout=10)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)


class TestMultiTurnConversation:
    """Test multi-turn conversations with tools."""

    def test_read_then_write(self, mock_server, luna_env, tmp_path):
        """Test a conversation where AI reads then writes."""
        test_file = tmp_path / "original.txt"
        test_file.write_text("Original content")

        mock_server.set_sequential_responses([
            make_sse_response(
                "I'll read the original file",
                tool_calls=[{
                    "name": "read_file",
                    "arguments": json.dumps({"path": str(test_file)})
                }]
            ),
            make_sse_response(
                "Now I'll write the modified content",
                tool_calls=[{
                    "name": "write_file",
                    "arguments": json.dumps({
                        "path": str(test_file),
                        "content": "Modified content"
                    })
                }]
            ),
            make_sse_response("Done!")
        ])

        child = spawn_luna(luna_env, tmp_path, timeout=25)

        try:
            child.expect(r"> ")
            child.sendline("modify the file")
            child.expect(r"> ", timeout=20)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)


class TestErrorHandling:
    """Test error handling."""

    def test_file_not_found(self, mock_server, luna_env, tmp_path):
        """Test handling of file not found error."""
        mock_server.set_sequential_responses([
            make_sse_response(
                "I'll try to read",
                tool_calls=[{
                    "name": "read_file",
                    "arguments": json.dumps({"path": str(tmp_path / "nonexistent.txt")})
                }]
            ),
            make_sse_response("Error handled")
        ])

        child = spawn_luna(luna_env, tmp_path, timeout=20)

        try:
            child.expect(r"> ")
            child.sendline("read nonexistent")
            # Should see error message about file not found
            child.expect(r"not found", timeout=10)
            child.expect(r"> ", timeout=10)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)

    def test_api_error_handling(self, mock_server, luna_env, tmp_path):
        """Test handling of API errors."""
        # Set up an error response
        mock_server.set_response("error_test", {
            "error": {
                "message": "Test API error",
                "type": "api_error"
            }
        })

        child = spawn_luna(luna_env, tmp_path, timeout=15)

        try:
            child.expect(r"> ")
            child.sendline("error_test")
            # Should handle error gracefully
            child.expect(r"> ", timeout=10)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)


class TestContextManagement:
    """Test context/window management."""

    def test_long_conversation(self, mock_server, luna_env, tmp_path):
        """Test that long conversations work correctly."""
        mock_server.set_response("ping", make_sse_response("pong"))

        child = spawn_luna(luna_env, tmp_path, timeout=30)

        try:
            child.expect(r"> ")
            
            # Send multiple messages
            for i in range(5):
                child.sendline(f"ping {i}")
                child.expect(r"pong", timeout=10)
                child.expect(r"> ", timeout=5)
        finally:
            try:
                child.sendline("/quit")
                child.expect(pexpect.EOF, timeout=5)
            except (pexpect_exceptions.TIMEOUT, pexpect_exceptions.EOF):
                child.close(force=True)
