"""check_lua_gate.py, the PreToolUse hook that keeps an agent's checks to
groups of the suites (tests/suites.lua): a command running every suite is
denied, naming the way to run groups; any other passes untouched."""
import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check_lua_gate.py"


def decide(command, tool="Bash"):
    hook_input = {"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": {"command": command}}
    done = subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(hook_input),
                          capture_output=True, text=True, check=True)
    if not done.stdout.strip():
        return None
    out = json.loads(done.stdout)["hookSpecificOutput"]
    return out["permissionDecision"], out["permissionDecisionReason"]


def test_every_suite_at_once_is_denied():
    for command in [
        ".devtools/bin/check_lua.sh all",
        "sh .devtools/bin/check_lua.sh all 2>&1 | tail -3",
        "cd /x && ./.devtools/bin/check_lua.sh all",
        ".devtools/bin/run_lua_tests.sh",
        ".devtools/bin/run_lua_tests.sh 2>&1 | tail",
        "for t in tests/*_test.lua; do luajit $t; done",
    ]:
        decision = decide(command)
        assert decision is not None and decision[0] == "deny", command
        assert "--changed" in decision[1] and "suites.lua list" in decision[1], command


def test_groups_and_single_tests_pass():
    for command in [
        ".devtools/bin/check_lua.sh foundation war",
        ".devtools/bin/check_lua.sh --changed",
        ".devtools/bin/check_lua.sh --list",
        ".devtools/bin/run_lua_tests.sh tests/math_box_test.lua",
        "luajit tests/wetsands_navsearch_test.lua",
        "git log --oneline -3",
    ]:
        assert decide(command) is None, command


def test_naming_them_is_not_running_them():
    for command in [
        "git commit -q -F - <<'EOF'\nSubject\n\ncheck_lua.sh all is the operator's; a loop over tests/*_test.lua too\nEOF",
        'git commit -m "check_lua.sh all now refuses agents; run_lua_tests.sh takes files"',
        "grep -rn 'check_lua.sh all' docs",
        "cat > notes.md <<EOF\n.devtools/bin/run_lua_tests.sh\nEOF\necho done",
    ]:
        assert decide(command) is None, command


def test_a_run_after_a_heredoc_is_still_seen():
    decision = decide("cat > x <<'EOF'\nnothing\nEOF\n.devtools/bin/check_lua.sh all")
    assert decision is not None and decision[0] == "deny"


def test_the_operators_word_lets_the_whole_suite_through():
    assert decide("CHECK_LUA_ALL=1 .devtools/bin/check_lua.sh all") is None


def test_other_tools_pass():
    assert decide("check_lua.sh all", tool="Read") is None
