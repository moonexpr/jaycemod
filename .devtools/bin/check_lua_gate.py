#!/usr/bin/env python3
"""A PreToolUse hook (.claude/settings.json) that keeps an agent's Lua checks
to groups of the suites: tests/suites.lua groups the tests by major system,
and a command running every suite at once (`check_lua.sh all`, a bare
`run_lua_tests.sh`, a loop over tests/*_test.lua) is denied with the way to
run groups. The operator's word lets the whole suite through: a command
starting with CHECK_LUA_ALL=1."""
import json
import re
import sys

# Where a command starts: the line's start, after a separator, or after
# sh, bash or a loop's do; then the script by any path.
START = r"(?:^|[;&|(]\s*|\b(?:sh|bash|do|then)\s+)\s*(?:\S*/)?"
EVERY_SUITE = [
    re.compile(START + r"check_lua\.sh\s+all\b", re.M),
    re.compile(START + r"run_lua_tests\.sh[ \t]*($|[|;&>)]|2>)", re.M),
    re.compile(r"\bin\s+(?:\S*/)?tests/\*_test\.lua"),
]
OPERATORS_WORD = re.compile(r"^\s*CHECK_LUA_ALL=1\s")
# A heredoc's body (<<EOF ... EOF, quoted or not) and quoted strings are
# text the command is handed, not commands it runs.
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?^\s*\2\s*$", re.S | re.M)
QUOTED = re.compile(r"'[^']*'|\"(?:[^\"\\]|\\.)*\"")

REASON = (
    "Run the suites of the systems you changed, not all of them: "
    "`.devtools/bin/check_lua.sh --changed` (the groups your changes touch), "
    "`.devtools/bin/check_lua.sh GROUP...` (named groups), "
    "or `luajit tests/<name>_test.lua` for one file. "
    "The groups: `luajit .devtools/bin/suites.lua list`. "
    "Only when the operator asks for the whole suite: prefix the command with CHECK_LUA_ALL=1."
)


def runs_every_suite(command: str) -> bool:
    if OPERATORS_WORD.match(command):
        return False
    run = QUOTED.sub("''", HEREDOC.sub("", command))
    return any(p.search(run) for p in EVERY_SUITE)


def main() -> int:
    hook_input = json.load(sys.stdin)
    if hook_input.get("tool_name") != "Bash":
        return 0
    if runs_every_suite(hook_input.get("tool_input", {}).get("command", "")):
        json.dump({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": REASON,
        }}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
