#!/usr/bin/env python3
"""The sandcastle MCP server: the dedicated server's Lua, console, breakpoints,
stacks and events as tools, so Claude needs no Bash to reach them.

  gmod_mcp.py          serve MCP over stdio (the sandcastle-dev plugin starts it)

Each tool takes `instance` (1, the main server, by default; srcds.py
--instance). Lua goes through luadev's socket (server_lua.py), breakpoints
and errors through its ops (server_root/sandcastle_debug.lua), console
commands through RCON (srcds.py), and the logs are read from disk. Events a
listener or a breakpoint pushes are lines of the watch log: watch_events
reads them; to wait on one, follow it under the Monitor tool with
server_watch.py (the listeners tool says how).

MCP over stdio is newline-delimited JSON-RPC 2.0; this speaks the part a
tools-only server needs (initialize, ping, tools/list, tools/call) with the
standard library alone, as the machine's python3 is 3.9 and the mcp package
wants 3.10.
"""
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional, Protocol, TextIO

from server_lua import BridgeDown, NoReply, OpFailed, Realm, Reply

SERVER_INFO = {"name": "gmod", "version": "0.1.0"}
LISTENERS = Path(__file__).resolve().parent / "listeners"
LOG_TAIL_BYTES = 512 * 1024  # how much of a log's end is read
DEFAULT_LINES = 40
LUA_TIMEOUT = 10
METHOD_NOT_FOUND, INTERNAL_ERROR = -32601, -32603
INSTANCE = {"type": "integer", "minimum": 1, "default": 1, "description": "which server (srcds.py --instance)"}


class Server(Protocol):
    def lua(self, realm: Realm, code: str, instance: int) -> Reply: ...
    def op(self, name: str, args: dict, instance: int) -> object: ...
    def rcon(self, command: str, instance: int) -> str: ...
    def console_log(self, instance: int) -> str: ...
    def watch_log(self, instance: int) -> str: ...


class ToolError(Exception):
    """A tool's refusal: its message is the error result's text."""


# What the answers read like

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\r")


def plain(text: str) -> str:
    return ANSI.sub("", text)


def tail(text: str, lines: int, pattern: Optional[str]) -> str:
    kept = text.splitlines()
    if pattern:
        rx = re.compile(pattern)
        kept = [line for line in kept if rx.search(line)]
    return "\n".join(kept[-lines:])


def as_list(value: object) -> list:
    return value if isinstance(value, list) else []  # GMod's JSON writes an empty table as {}


def show_stack(frames: object) -> str:
    out = []
    for i, f in enumerate(as_list(frames), 1):
        out.append(f"#{i} {f['name']}  {f['source']}:{f['line']}")
        for kind in ("locals", "upvalues"):
            values = as_list(f.get(kind))
            if values:
                out.append(f"   {kind}: " + ", ".join(f"{v['name']}={v['value']}" for v in values))
    return "\n".join(out)


def show_hits(hits: object) -> str:
    hits = as_list(hits)
    if not hits:
        return "no hits yet"
    return "\n\n".join(f"hit {h['n']} at {h['time']:.2f}\n{show_stack(h['frames'])}" for h in hits)


def show_breakpoints(bps: object) -> str:
    lines = []
    for bp in as_list(bps):
        line = f"bp{bp['id']} {bp['file']}:{bp['line']} {bp['mode']} {bp['state']} {bp['hits']}/{bp['max']}"
        if bp.get("condition"):
            line += f" if {bp['condition']}"
        lines.append(line)
    return "\n".join(lines) or "no breakpoints"


def show_errors(errors: object) -> str:
    out = []
    for e in as_list(errors):
        out.append(f"error {e['id']} (seq {e['seq']}) first {e['time']:.2f}, last {e['last']:.2f} "
                   f"(x{e['count']}, {e['realm']}): {e['error']}")
        for f in as_list(e.get("stack")):
            out.append(f"   {f.get('Function') or '?'}  {f['File']}:{f['Line']}")
    return "\n".join(out) or "no Lua errors"


def show_game_events(events: object) -> str:
    lines = []
    for e in as_list(events):
        fields = " ".join(f"{f['name']}={f['value']}" for f in as_list(e.get("fields")))
        lines.append(f"{e['id']} at {e['time']:.2f} {e['name']} -> {e['players']} players: {fields}".rstrip(": "))
    return "\n".join(lines) or "no game events"


def show_console(lines: object) -> str:
    return "\n".join(f"{l['id']} at {l['time']:.2f} {l['text']}" for l in as_list(lines)) or "no console lines"


def show_reply(reply: Reply) -> str:
    lines = list(reply.output) + [f"=> {v}" for v in reply.returns]
    if reply.clients is not None:
        lines.append(f"(sent to {reply.clients} clients)")
    if reply.error:
        lines.append(f"ERROR {reply.error}")
    return "\n".join(lines) or "(nothing printed or returned)"


# The tools

@dataclass(frozen=True)
class Tool:
    name: str
    description: str
    properties: dict
    required: tuple
    handler: Callable[["Mcp", dict], str]

    def schema(self) -> dict:
        return {"name": self.name, "description": self.description,
                "inputSchema": {"type": "object", "properties": {**self.properties, "instance": INSTANCE},
                                "required": list(self.required)}}


def given(args: dict, *names: str) -> dict:
    return {n: args[n] for n in names if args.get(n) is not None}


def lua_run(mcp: "Mcp", args: dict) -> str:
    reply = mcp.server.lua(Realm(args.get("realm", "sv")), args["code"], args.get("instance", 1))
    text = show_reply(reply)
    if reply.error:
        raise ToolError(text)
    return text


def op(name: str, show: Callable[[object], str], *names: str) -> Callable[["Mcp", dict], str]:
    return lambda mcp, args: show(mcp.server.op(name, given(args, *names), args.get("instance", 1)))


def show_state(state: object) -> str:
    paused = state["paused"]
    head = f"armed: {str(state['armed']).lower()}"
    if not paused:
        return head + "\nnot paused"
    who = f"bp{paused['bp']}" if paused.get("bp") else "a step"
    return f"{head}\npaused by {who}; the server is frozen until debug_resume\n{show_stack(paused['frames'])}"


def show_listeners(directory: Path) -> str:
    lines = []
    for path in sorted(directory.glob("*.lua")):
        first = next((l[2:].strip() for l in path.read_text().splitlines() if l.startswith("--")), "")
        lines.append(f"{path.stem}: {first}")
    lines.append("")
    lines.append("Follow one under the Monitor tool: python3 .devtools/bin/server_watch.py --listen NAME "
                 "--run 'COMMAND' [--instance N]. It arms .devtools/bin/listeners/NAME.lua, runs the console "
                 "command, and prints each event until NAME is met (exit 0) or times out or errors (exit 1). "
                 "A new long-running command gets a listener by writing one such file (Watch.Task).")
    return "\n".join(lines)


TOOLS = (
    Tool("lua_run", "Run Lua on the dedicated server through luadev; answers what it printed (print, MsgN), "
         "its return values as '=> value', and any error. Prefer `return` for values. Globals stay until the "
         "map changes. realm cl/sh also sends it to every client, which never answer.",
         {"code": {"type": "string"}, "realm": {"type": "string", "enum": ["sv", "cl", "sh"], "default": "sv"}},
         ("code",), lua_run),
    Tool("rcon", "Run a console command on the dedicated server (changelevel, status, convars, mp_* and ns_* "
         "commands); answers RCON's reply. Output a command prints to the console arrives in console_log.",
         {"command": {"type": "string"}}, ("command",),
         lambda mcp, args: mcp.server.rcon(args["command"], args.get("instance", 1)) or "(no reply)"),
    Tool("console_log", "The end of the dedicated server's console, terminal codes removed; `grep` keeps only "
         "lines matching a regular expression.",
         {"lines": {"type": "integer", "default": DEFAULT_LINES}, "grep": {"type": "string"}}, (),
         lambda mcp, args: tail(plain(mcp.server.console_log(args.get("instance", 1))),
                                args.get("lines", DEFAULT_LINES), args.get("grep")) or "(nothing)"),
    Tool("lua_errors", "The newest distinct Lua errors the server raised (OnLuaError, a ring of 50), each with its "
         "stack, how often it happened and when first and last. A repeat counts on its entry instead of taking a "
         "place. `since`: only errors new or repeated after that seq.",
         {"since": {"type": "integer", "default": 0}}, (), op("lua_errors", show_errors, "since")),
    Tool("game_events", "The newest game events the server fired (the event library's E.Fire; a ring of 200), "
         "each with its fields and how many players it was sent to. `name` keeps one event's; `since` only those "
         "after that id.",
         {"name": {"type": "string"}, "since": {"type": "integer", "default": 0}}, (),
         op("game_events", show_game_events, "name", "since")),
    Tool("console_messages", "The newest lines Lua printed on the server (print, Msg, MsgN, MsgC; a ring of 500). "
         "`grep` keeps lines holding that text; `since` only those after that id. Engine output (map loads, "
         "RCON) is not here: read it with console_log.",
         {"grep": {"type": "string"}, "since": {"type": "integer", "default": 0}}, (),
         op("console_messages", show_console, "grep", "since")),
    Tool("breakpoint_set", "Set a breakpoint at a file and line. `file` may be the repo path "
         "(addon/gamemodes/sandcastle/gamemode/foundation/rounds.lua) or its tail (foundation/rounds.lua); "
         "luadev chunks are 'server_lua'. mode snapshot (default) captures the stack with locals and upvalues "
         "and goes on, up to `hits` times (default 5): read them with breakpoint_hits. mode pause freezes the "
         "whole server at the line (clients time out after ~30 s) until debug_resume or `pause_limit` seconds "
         "(default 60). `condition` is a Lua expression over the frame's locals. Each hit is also a watch event "
         "'bp<id> hit'. The server runs slower while any breakpoint is active.",
         {"file": {"type": "string"}, "line": {"type": "integer", "minimum": 1}, "condition": {"type": "string"},
          "mode": {"type": "string", "enum": ["snapshot", "pause"], "default": "snapshot"},
          "hits": {"type": "integer", "minimum": 1, "default": 5}, "pause_limit": {"type": "number", "default": 60}},
         ("file", "line"), op("bp_set", lambda bp: show_breakpoints([bp]), "file", "line", "condition", "mode",
                              "hits", "pause_limit")),
    Tool("breakpoint_list", "Every breakpoint with its state (active, done, error) and hits so far.", {}, (),
         op("bp_list", show_breakpoints)),
    Tool("breakpoint_clear", "Clear one breakpoint by id, or every one with no id.",
         {"id": {"type": "integer"}}, (), op("bp_clear", show_breakpoints, "id")),
    Tool("breakpoint_hits", "The stacks a breakpoint captured (the newest 20), each frame with its locals and "
         "upvalues. `since`: only hits after that count.",
         {"id": {"type": "integer"}, "since": {"type": "integer", "default": 0}}, ("id",),
         op("bp_hits", show_hits, "id", "since")),
    Tool("debug_state", "Whether breakpoints are armed, and if the server is paused, where, with the stack.",
         {}, (), op("debug_state", show_state)),
    Tool("debug_eval", "Evaluate a Lua expression (or run a statement). While paused it sees the paused stack's "
         "frame `frame` (1, the top, by default): its locals, then upvalues, then globals; otherwise globals.",
         {"expr": {"type": "string"}, "frame": {"type": "integer", "minimum": 1, "default": 1}}, ("expr",),
         op("debug_eval", str, "expr", "frame")),
    Tool("debug_resume", "Resume a paused server: continue, or step in (into calls), over (to the next line of "
         "this function or its caller) or out (back to the caller); a step pauses again where it lands.",
         {"kind": {"type": "string", "enum": ["continue", "in", "over", "out"], "default": "continue"}}, (),
         op("debug_resume", lambda kind: f"resumed: {kind}", "kind")),
    Tool("watch_events", "The newest lines of the server's event log (listener progress, met/timeout, "
         "breakpoint hits and pauses, Lua errors): '<time> <name> <kind> <text>'. `name` keeps one name's.",
         {"lines": {"type": "integer", "default": DEFAULT_LINES}, "name": {"type": "string"}}, (),
         lambda mcp, args: tail(mcp.server.watch_log(args.get("instance", 1)), args.get("lines", DEFAULT_LINES),
                                f"^\\S+ {re.escape(args['name'])} " if args.get("name") else None) or "(no events)"),
    Tool("listeners", "The listeners there are for long-running commands (nav generation and the like), and "
         "how to follow one to its end under the Monitor tool.", {}, (),
         lambda mcp, args: show_listeners(mcp.listeners)),
)
BY_NAME = {t.name: t for t in TOOLS}


# The protocol

class Mcp:
    def __init__(self, server: Server, listeners: Path):
        self.server, self.listeners = server, listeners

    def call(self, name: str, args: dict) -> dict:
        tool = BY_NAME.get(name)
        try:
            if tool is None:
                raise ToolError(f"no tool {name}")
            return {"content": [{"type": "text", "text": tool.handler(self, args)}]}
        except (ToolError, OpFailed, BridgeDown, NoReply) as e:
            return {"content": [{"type": "text", "text": str(e)}], "isError": True}

    def answer(self, request: dict) -> Optional[dict]:
        method, params = request.get("method"), request.get("params") or {}
        if "id" not in request:
            return None  # a notification
        if method == "initialize":
            result = {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                      "capabilities": {"tools": {}}, "serverInfo": SERVER_INFO}
        elif method == "ping":
            result = {}
        elif method == "tools/list":
            result = {"tools": [t.schema() for t in TOOLS]}
        elif method == "tools/call":
            result = self.call(params["name"], params.get("arguments") or {})
        else:
            return {"jsonrpc": "2.0", "id": request["id"],
                    "error": {"code": METHOD_NOT_FOUND, "message": f"no method {method}"}}
        return {"jsonrpc": "2.0", "id": request["id"], "result": result}

    def serve(self, stdin: TextIO, stdout: TextIO) -> None:
        for line in stdin:
            if not line.strip():
                continue
            request = json.loads(line)
            try:
                reply = self.answer(request)
            except Exception as e:  # ours: logged, and the client hears it failed
                print(f"gmod_mcp: {request.get('method')} failed: {e!r}", file=sys.stderr)
                reply = {"jsonrpc": "2.0", "id": request.get("id"),
                         "error": {"code": INTERNAL_ERROR, "message": f"{type(e).__name__}: {e}"}}
            if reply is not None:
                stdout.write(json.dumps(reply) + "\n")
                stdout.flush()


# The real server

def read_end(path: Path) -> str:
    if not path.exists():
        return ""
    with path.open("rb") as f:
        size = f.seek(0, 2)
        f.seek(max(0, size - LOG_TAIL_BYTES))
        return f.read().decode("utf-8", "replace")


class DedicatedServer:
    def lua(self, realm: Realm, code: str, instance: int) -> Reply:
        from server_lua import address, run
        return run(realm, code, address(instance), timeout=LUA_TIMEOUT)

    def op(self, name: str, args: dict, instance: int) -> object:
        from server_lua import address, call_op
        return call_op(name, args, address(instance), timeout=LUA_TIMEOUT)

    def rcon(self, command: str, instance: int) -> str:
        from server_root import Instance
        from srcds import AuthFailed, ServerDown, rcon_command
        try:
            return rcon_command(Instance(instance), command)
        except (ServerDown, AuthFailed, OSError) as e:
            raise ToolError(f"rcon: {e}") from e

    def console_log(self, instance: int) -> str:
        from server_root import Instance
        from srcds import InstanceFiles
        return read_end(InstanceFiles.of(Instance(instance)).log)

    def watch_log(self, instance: int) -> str:
        from server_root import Instance
        from server_watch import log_path
        return read_end(log_path(Instance(instance)))


def main() -> int:
    Mcp(DedicatedServer(), LISTENERS).serve(sys.stdin, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
