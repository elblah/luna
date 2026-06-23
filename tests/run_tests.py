#!/usr/bin/env python3
"""
Integration test runner for Luna (Lua).

Starts a mock API server and runs pexpect-based tests.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mock_server import MockServer, make_sse_response

try:
    import pexpect
    from pexpect import exceptions as pexpect_exceptions
except ImportError:
    print("pexpect not installed. Run: pip install pexpect")
    sys.exit(1)


def spawn_luna(env, cwd, timeout=20):
    main_script = os.path.join(cwd, "main.lua")
    return pexpect.spawn(
        f"luajit {main_script}",
        env=env,
        cwd=cwd,
        timeout=timeout,
        encoding='utf-8'
    )


def test_simple_response(mock_server, luna_path):
    """Test basic AI response."""
    print("\n=== Test: Simple Response ===")
    mock_server.clear_responses()
    mock_server.set_response("hello", make_sse_response("Hello, human!"))
    
    env = os.environ.copy()
    env["PATH"] = "/usr/bin:/bin"  # Ensure luajit is accessible
    env["API_PROVIDER"] = "openai"
    env["API_BASE_URL"] = mock_server.get_api_base()
    env["API_MODEL"] = "test-model"
    env["MAX_TOKENS"] = "2000"
    # Unset conflicting env vars
    env.pop("API_ENDPOINT", None)
    env.pop("OPENAI_API_KEY", None)
    
    child = spawn_luna(env, luna_path)
    try:
        child.expect(r"> ")
        child.sendline("hello")
        child.expect(r"Hello, human!", timeout=10)
        child.expect(r"> ", timeout=5)
        print("PASS: Got response")
    except Exception as e:
        print(f"FAIL: {e}")
        return False
    finally:
        child.close(force=True)
    return True


def test_markdown(mock_server, luna_path):
    """Test markdown formatting."""
    print("\n=== Test: Markdown Formatting ===")
    mock_server.clear_responses()
    mock_server.set_response("markdown", make_sse_response("# Title\n**bold**"))
    
    env = os.environ.copy()
    env["PATH"] = "/usr/bin:/bin"
    env["API_PROVIDER"] = "openai"
    env["API_BASE_URL"] = mock_server.get_api_base()
    env["API_MODEL"] = "test-model"
    env["MAX_TOKENS"] = "2000"
    env.pop("API_ENDPOINT", None)
    env.pop("OPENAI_API_KEY", None)
    
    child = spawn_luna(env, luna_path)
    try:
        child.expect(r"> ")
        child.sendline("show markdown")
        child.expect(r"Title", timeout=10)
        child.expect(r"> ", timeout=5)
        print("PASS: Markdown rendered")
    except Exception as e:
        print(f"FAIL: {e}")
        return False
    finally:
        child.close(force=True)
    return True


def test_tool_execution(mock_server, luna_path):
    """Test tool execution (read_file)."""
    print("\n=== Test: Tool Execution ===")
    test_file_path = os.path.join(luna_path, "test_data.txt")
    with open(test_file_path, "w") as f:
        f.write("Hello World\nLine 2")
    
    # Use set_sequential_responses for multi-turn (tool call + response)
    mock_server.set_sequential_responses([
        make_sse_response("I'll read it", tool_calls=[{
            "name": "read_file",
            "arguments": json.dumps({"path": test_file_path})
        }]),
        make_sse_response("File has 2 lines")
    ])
    
    env = os.environ.copy()
    env["PATH"] = "/usr/bin:/bin"
    env["API_PROVIDER"] = "openai"
    env["API_BASE_URL"] = mock_server.get_api_base()
    env["API_MODEL"] = "test-model"
    env["MAX_TOKENS"] = "2000"
    env["MINI_SANDBOX"] = "1"
    env.pop("API_ENDPOINT", None)
    env.pop("OPENAI_API_KEY", None)
    
    child = spawn_luna(env, luna_path)
    try:
        child.expect(r"> ")
        child.sendline("read the file")
        # Wait for final prompt - tool result should be shown
        child.expect(r"> ", timeout=30)
        print("PASS: Tool executed")
    except Exception as e:
        print(f"FAIL: {e}")
        return False
    finally:
        child.close(force=True)
    return True


def test_multi_turn(mock_server, luna_path):
    """Test multi-turn conversation."""
    print("\n=== Test: Multi-Turn Conversation ===")
    # Use 3 different patterns to match different messages
    mock_server.set_response("first", make_sse_response("First response"))
    mock_server.set_response("second", make_sse_response("Second response"))
    mock_server.set_response("third", make_sse_response("Third response"))
    
    env = os.environ.copy()
    env["PATH"] = "/usr/bin:/bin"
    env["API_PROVIDER"] = "openai"
    env["API_BASE_URL"] = mock_server.get_api_base()
    env["API_MODEL"] = "test-model"
    env["MAX_TOKENS"] = "2000"
    env.pop("API_ENDPOINT", None)
    env.pop("OPENAI_API_KEY", None)
    
    child = spawn_luna(env, luna_path)
    try:
        child.expect(r"> ")
        
        # First message
        child.sendline("first")
        child.expect(r"First response", timeout=15)
        child.expect(r"> ", timeout=10)
        
        # Second message
        child.sendline("second")
        child.expect(r"Second response", timeout=15)
        child.expect(r"> ", timeout=10)
        
        # Third message
        child.sendline("third")
        child.expect(r"Third response", timeout=15)
        child.expect(r"> ", timeout=10)
        
        print("PASS: Multi-turn works")
    except Exception as e:
        print(f"FAIL: {e}")
        return False
    finally:
        child.close(force=True)
    return True


def main():
    # Start mock server
    print("Starting mock API server...")
    mock_server = MockServer()
    mock_server.start()
    print(f"Mock server on port {mock_server.get_port()}")
    
    # Luna project directory (where main.lua is)
    luna_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    results = []
    results.append(test_simple_response(mock_server, luna_path))
    results.append(test_markdown(mock_server, luna_path))
    results.append(test_tool_execution(mock_server, luna_path))
    results.append(test_multi_turn(mock_server, luna_path))
    
    mock_server.stop()
    
    print("\n" + "="*50)
    passed = sum(results)
    total = len(results)
    print(f"Results: {passed}/{total} tests passed")
    
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
