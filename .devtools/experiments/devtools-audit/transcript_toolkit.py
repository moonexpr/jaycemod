#!/usr/bin/env python3
# dt-brief: How the live-server toolkit (gmod MCP, srcds.py, dt, the dev workbench) was used across Claude Code transcripts
"""Measure the live-server toolkit's use from Claude Code's transcripts, as aggregates only.

  transcript_toolkit.py                 print the summary, write the JSON beside the other artifacts
  transcript_toolkit.py --json PATH     write the JSON there

Reads ~/.claude/projects/*sandcastle*/*.jsonl and *jaycemod*/*.jsonl (the project was
sandcastle until 2026-11-12). Every assistant tool_use is classified into a toolkit
door (gmod MCP tool, dt short name, srcds.py subcommand, server_lua.py, ...) and, for
Lua sent to the server, into what the Lua does (dev.reload, scenario, a map change,
a read). Counts, retries, errors, weekly adoption and call sequences come out; no
transcript text does, beyond short normalised command templates.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import glob
import json
import os
import re
import statistics
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PROJECTS = os.path.expanduser("~/.claude/projects")
PATTERNS = ("*sandcastle*", "*jaycemod*")

# Bash command → door. First match wins; order matters.
BASH_DOORS = [
    (re.compile(r"\bsrcds\.py\s+(?:--instance\s+\d+\s+)?(\w+)"), lambda m: f"srcds.py {m.group(1)}"),
    (re.compile(r"\bdt\s+(lua|rcon|watch|srcds|gmod)\b(?:\s+(\w+))?"), lambda m: f"dt {m.group(1)}" + (f" {m.group(2)}" if m.group(1) == "gmod" and m.group(2) else "")),
    (re.compile(r"\bdt\s+rag/history\s+(\w+)"), lambda m: f"dt rag/history {m.group(1)}"),
    (re.compile(r"\bserver_lua\.py"), lambda m: "server_lua.py"),
    (re.compile(r"\bgmod_lua\.py"), lambda m: "gmod_lua.py"),
    (re.compile(r"\bserver_watch\.py"), lambda m: "server_watch.py"),
    (re.compile(r"\blua_watch\.py"), lambda m: "lua_watch.py"),
    (re.compile(r"\bgmod_mcp\.py\s+(\w+)"), lambda m: f"gmod_mcp.py {m.group(1)}"),
    (re.compile(r"\bingame_(?:tests|one)\.py"), lambda m: "ingame_tests.py"),
    (re.compile(r"\bcheck_lua\.sh\s*(--changed|all|\w+)?"), lambda m: "check_lua.sh " + (m.group(1) or "")),
    (re.compile(r"\brun_lua_tests\.sh"), lambda m: "run_lua_tests.sh"),
    (re.compile(r"\bluajit\s+\S*tests/\S+_test\.lua"), lambda m: "luajit a test"),
    (re.compile(r"\blua_format\.py"), lambda m: "lua_format.py"),
    (re.compile(r"\binstances\.py"), lambda m: "instances.py"),
    (re.compile(r"\badd_map\.py"), lambda m: "add_map.py"),
    (re.compile(r"\brcon\b"), lambda m: "rcon (other)"),
]

# What a Lua chunk or console command does.
LUA_INTENTS = [
    ("dev.reload", re.compile(r"dev\.reload\b|dev_reload\b")),
    ("dev.run", re.compile(r"dev\.run\b|dev_run\b")),
    ("scenario load/save", re.compile(r"scenario_(?:load|save)|dev\.scenario\.|dev_quick(?:load|save)")),
    ("harness", re.compile(r"dev\.harness\.|dev_harness|dev_pause|dev_resume|dev_step|dev_force_win|dev_timer")),
    ("map change", re.compile(r"\bchangelevel\b|\bmap\s+\w+_\w+")),
    ("limits off (mp_timelimit 0 ...)", re.compile(r"mp_timelimit\s+0|mp_winlimit\s+0|mp_maxrounds\s+0")),
    ("which map", re.compile(r"game\.GetMap\s*\(")),
    ("players / bots", re.compile(r"player\.GetAll|player\.GetCount|GetBots|bot_quota|tf_bot_quota|ns_bots")),
    ("soldiers / war state", re.compile(r"ents\.FindByClass|aiwar|WS\.War|wartactics|nextsoldier|NextSoldier")),
    ("rounds / timers", re.compile(r"round_manager|RoundState|GetRoundState|game_timer|team_round_timer")),
    ("hooks / timers added", re.compile(r"hook\.Add\s*\(|timer\.Create\s*\(|timer\.Simple\s*\(")),
    ("file / include", re.compile(r"\binclude\s*\(|\bfile\.Read|RunString|CompileFile|luadev")),
    ("convar", re.compile(r"GetConVar|RunConsoleCommand|game\.ConsoleCommand")),
    ("debug.getinfo", re.compile(r"debug\.getinfo")),
    ("print only", re.compile(r"^\s*print\s*\(")),
    ("return a value", re.compile(r"^\s*return\b")),
]

MONITOR_LIKE = re.compile(r"\bsleep\s+\d+|\bwhile\s+.*;\s*do|\bfor\s+\w+\s+in\s+.*;\s*do|\buntil\b", re.S)


def iter_events(path: str):
    with open(path, errors="ignore") as fh:
        for line in fh:
            try:
                yield json.loads(line)
            except ValueError:
                continue


def normalise(text: str, limit=70) -> str:
    text = re.sub(r"\s+", " ", text.strip())
    text = re.sub(r"\b\d+\b", "N", text)
    text = re.sub(r"\"[^\"]*\"|'[^']*'", "'…'", text)
    return text[:limit]


def classify(name: str, inp: dict):
    """→ (door, intent, template) or None when not a toolkit call."""
    if name.startswith("mcp__gmod__"):
        tool = name[len("mcp__gmod__"):]
        code = inp.get("code") or inp.get("command") or ""
        return f"gmod MCP {tool}", intent_of(code) if tool in ("lua_run", "rcon") else None, normalise(code)
    if name == "Bash":
        cmd = inp.get("command", "")
        for pattern, door in BASH_DOORS:
            m = pattern.search(cmd)
            if m:
                d = door(m).strip()
                lua = cmd
                return d, intent_of(lua) if d.startswith(("dt lua", "server_lua", "gmod_lua", "dt rcon", "srcds.py rcon", "dt gmod lua_run", "dt gmod rcon")) else None, normalise(cmd)
        return None
    return None


def intent_of(code: str):
    for label, pattern in LUA_INTENTS:
        if pattern.search(code):
            return label
    return "other"


def week_of(ts: str) -> str:
    d = dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).date()
    return str(d - dt.timedelta(days=d.weekday()))


def analyse() -> dict:
    files = []
    for pat in PATTERNS:
        files += glob.glob(os.path.join(PROJECTS, pat, "*.jsonl"))
    files = sorted(set(files))
    doors = collections.Counter()
    intents = collections.Counter()
    door_intents = collections.defaultdict(collections.Counter)
    templates = collections.defaultdict(collections.Counter)
    weekly = collections.defaultdict(collections.Counter)
    errors = collections.Counter()
    error_kinds = collections.defaultdict(collections.Counter)
    retries = collections.Counter()
    bigrams = collections.Counter()
    sessions_using = collections.Counter()
    per_session = collections.defaultdict(int)
    all_tools = collections.Counter()
    bash_loops = 0
    operator_friction = collections.Counter()
    first_seen, last_seen = {}, {}
    sessions_total = 0
    total_calls = 0
    for path in files:
        sessions_total += 1
        pending = {}  # tool_use id → door
        last_call = None  # (door, template, time)
        prev_door = None
        for ev in iter_events(path):
            kind = ev.get("type")
            msg = ev.get("message") or {}
            content = msg.get("content")
            if kind == "assistant" and isinstance(content, list):
                for block in content:
                    if block.get("type") != "tool_use":
                        continue
                    total_calls += 1
                    all_tools[block["name"]] += 1
                    hit = classify(block["name"], block.get("input") or {})
                    if block["name"] == "Bash" and MONITOR_LIKE.search((block.get("input") or {}).get("command", "")):
                        bash_loops += 1
                    if not hit:
                        continue
                    door, intent, template = hit
                    ts = ev.get("timestamp", "")
                    doors[door] += 1
                    pending[block["id"]] = door
                    per_session[path] += 1
                    if intent:
                        intents[intent] += 1
                        door_intents[door][intent] += 1
                    templates[door][template] += 1
                    if ts:
                        weekly[week_of(ts)][door] += 1
                        first_seen.setdefault(door, ts)
                        last_seen[door] = ts
                    if prev_door and prev_door != door:
                        bigrams[(prev_door, door)] += 1
                    prev_door = door
                    when = dt.datetime.fromisoformat(ts.replace("Z", "+00:00")) if ts else None
                    if last_call and last_call[0] == door and last_call[1] == template and when and last_call[2] \
                            and (when - last_call[2]).total_seconds() < 300:
                        retries[door] += 1
                    last_call = (door, template, when)
            elif kind == "user" and isinstance(content, list):
                for block in content:
                    if block.get("type") == "tool_result" and block.get("tool_use_id") in pending:
                        door = pending.pop(block["tool_use_id"])
                        if block.get("is_error"):
                            errors[door] += 1
                            text = block.get("content")
                            if isinstance(text, list):
                                text = " ".join(t.get("text", "") for t in text if isinstance(t, dict))
                            error_kinds[door][normalise(str(text or ""), 60)] += 1
            elif kind == "user" and isinstance(content, str):
                low = content.lower()
                for key in ("restart", "server is down", "bridge down", "not reload", "didn't reload", "did not reload",
                            "changelevel", "change map", "change the map", "timed out", "stuck"):
                    if key in low:
                        operator_friction[key] += 1
        if per_session[path]:
            sessions_using["sessions with a toolkit call"] += 1
    calls = [n for n in per_session.values() if n]
    return {
        "files": len(files), "sessions": sessions_total, "sessions_using": sessions_using["sessions with a toolkit call"],
        "total_tool_calls": total_calls, "toolkit_calls": sum(doors.values()),
        "calls_per_session_median": statistics.median(calls) if calls else 0,
        "calls_per_session_max": max(calls) if calls else 0,
        "doors": doors.most_common(), "intents": intents.most_common(),
        "door_intents": {d: c.most_common(8) for d, c in door_intents.items()},
        "templates": {d: c.most_common(8) for d, c in templates.items() if sum(c.values()) >= 20},
        "weekly": {w: dict(c) for w, c in sorted(weekly.items())},
        "errors": errors.most_common(), "error_kinds": {d: c.most_common(5) for d, c in error_kinds.items()},
        "retries": retries.most_common(), "bigrams": [(a, b, n) for (a, b), n in bigrams.most_common(25)],
        "bash_loops": bash_loops, "all_tools": all_tools.most_common(20),
        "operator_friction": operator_friction.most_common(),
        "first_seen": {d: t[:10] for d, t in first_seen.items()}, "last_seen": {d: t[:10] for d, t in last_seen.items()},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--json", type=Path, default=REPO / ".devtools" / "artifacts" / "transcript-toolkit.json")
    args = parser.parse_args()
    report = analyse()
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=1))
    print(f"transcripts {report['files']} sessions, {report['sessions_using']} with a toolkit call; "
          f"{report['toolkit_calls']} toolkit calls of {report['total_tool_calls']} tool calls; "
          f"median {report['calls_per_session_median']} a session, max {report['calls_per_session_max']}")
    print("\nDOORS"); [print(f"  {n:5}  {d}") for d, n in report["doors"]]
    print("\nINTENTS of Lua and console commands"); [print(f"  {n:5}  {i}") for i, n in report["intents"]]
    print("\nERRORS by door"); [print(f"  {n:5}  {d}  ({report['errors'] and round(n * 100 / dict(report['doors'])[d])}%)") for d, n in report["errors"]]
    print("\nERROR KINDS")
    for d, kinds in report["error_kinds"].items():
        for k, n in kinds[:3]:
            print(f"  {n:4}  {d}: {k}")
    print("\nRETRIES (same door, same command, within 5 min)"); [print(f"  {n:5}  {d}") for d, n in report["retries"]]
    print("\nSEQUENCES"); [print(f"  {n:5}  {a} → {b}") for a, b, n in report["bigrams"][:18]]
    print("\nTOP TEMPLATES")
    for d, ts in report["templates"].items():
        print(f"  {d}")
        for t, n in ts[:5]:
            print(f"    {n:4}  {t}")
    print("\nWEEKLY (door → count)")
    for w, c in report["weekly"].items():
        top = sorted(c.items(), key=lambda kv: -kv[1])[:6]
        print(f"  {w}  " + ", ".join(f"{d} {n}" for d, n in top))
    print(f"\nBash loops / sleeps: {report['bash_loops']}")
    print("OPERATOR FRICTION words in prompts:", report["operator_friction"])
    print("ALL TOOLS:", report["all_tools"][:12])
    print("FIRST SEEN:", {d: t for d, t in sorted(report['first_seen'].items(), key=lambda kv: kv[1])})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
