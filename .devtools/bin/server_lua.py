#!/usr/bin/env python3
"""Run Lua on the dedicated server through luadev, and print what it printed.

  server_lua.py 'print(game.GetMap())'          run on the server
  server_lua.py -f script.lua                   run a file on the server
  server_lua.py <<'LUA'                         run stdin (no code, or "-"): no quoting
  server_lua.py 'return #player.GetAll()'       return values print as "=> ..."
  server_lua.py --realm cl 'chat.AddText("hi")' send to every client (no reply)
  server_lua.py --realm sh 'return CLIENT'      both; the reply is the server's
  server_lua.py --instance 2 '...'              a second server's (srcds.py --instance 2)

Use this, not `srcds.py rcon 'lua_run ...'`: lua_run's output only reaches the
logs, quoting through RCON mangles code, and a long chunk does not fit.

The server's autorun server_root/luadev_socket.lua (wired by server_root.py)
loads LuaSocket (lua/bin/gmsv_luasocket_win64.dll) and listens on
127.0.0.1:27098, beside the 27099 that luadev's socketdev holds in the
operator's game. A request is three lines, realm, label and the code's
length in bytes, then the code. The server runs it with luadev.RunOnServer
(or RunOnClients, or both), capturing print and MsgN while it runs, and
answers on the same connection with JSON: output, returns, error, and for
cl/sh the number of clients it was sent to. Clients do not answer.
"""
from __future__ import annotations

import argparse
import json
import socket
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional, TextIO

from server_root import LOCALHOST, Instance



def address(instance: int) -> tuple[str, int]:
    """The instance's luadev socket (server_root.Instance.luadev_port)."""
    return (LOCALHOST, Instance(instance).luadev_port)


ADDRESS = address(1)
LABEL = "server_lua"


class Realm(Enum):
    SERVER = "sv"
    CLIENT = "cl"
    SHARED = "sh"


@dataclass(frozen=True)
class Reply:
    output: list[str]
    returns: list[str]
    error: str | None
    clients: int | None


class BridgeDown(Exception):
    pass


class NoReply(Exception):
    pass


def frame(realm: Realm, code: str, label: str) -> bytes:
    if "\n" in label:
        raise ValueError(f"a label is one line: {label!r}")
    body = code.encode()
    return f"{realm.value}\n{label}\n{len(body)}\n".encode() + body


def as_list(value: object) -> list[str]:
    # util.TableToJSON writes an empty table as {}
    return [str(v) for v in value] if isinstance(value, list) else []


def parse_reply(data: bytes) -> Reply:
    d = json.loads(data)
    clients = d.get("clients")
    return Reply(as_list(d.get("output")), as_list(d.get("returns")), d.get("error"),
                 None if clients is None else int(clients))


def run(realm: Realm, code: str, address: tuple[str, int] = ADDRESS, timeout: float = 10) -> Reply:
    try:
        conn = socket.create_connection(address, timeout=timeout)
    except OSError as e:
        raise BridgeDown(f"{address[0]}:{address[1]} not reachable ({e}); is the server up with a map loaded?") from e
    with conn:
        conn.sendall(frame(realm, code, LABEL))
        data = b""
        try:
            while chunk := conn.recv(65536):
                data += chunk
        except socket.timeout as e:
            raise NoReply(f"no reply within {timeout}s (did the chunk hang?)") from e
    if not data:
        raise NoReply("the server closed the connection without a reply (see the end of .devtools/artifacts/srcds.log)")
    return parse_reply(data)


STDIN_CODE = "-"


def chunk_source(code: Optional[str], file: Optional[Path], stdin: TextIO) -> str:
    """The chunk to run: the argument, else the file, else stdin (also for "-")."""
    if file is not None:
        return file.read_text()
    if code is None or code == STDIN_CODE:
        return stdin.read()
    return code


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("code", nargs="?")
    ap.add_argument("-f", "--file", type=Path)
    ap.add_argument("--realm", choices=[r.value for r in Realm], default="sv")
    ap.add_argument("--timeout", type=float, default=10)
    ap.add_argument("--instance", type=int, default=1, help="which server (srcds.py --instance)")
    args = ap.parse_args()
    code = chunk_source(args.code, args.file, sys.stdin)
    try:
        reply = run(Realm(args.realm), code, address(args.instance), timeout=args.timeout)
    except BridgeDown as e:
        print(f"bridge down: {e}", file=sys.stderr)
        return 2
    except NoReply as e:
        print(str(e), file=sys.stderr)
        return 3
    for line in reply.output:
        print(line)
    for value in reply.returns:
        print(f"=> {value}")
    if reply.clients is not None:
        print(f"(sent to {reply.clients} clients)")
    if reply.error:
        print(f"ERROR {reply.error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
