#!/usr/bin/env python3
"""Run Lua in a running Garry's Mod through luadev's socket, and print what it printed.

  gmod_lua.py 'print(game.GetMap())'           run on the server
  gmod_lua.py --realm cl -f script.lua         run a file on the clients
  gmod_lua.py --realm sh 'return CLIENT'       run on both

luadev's socketdev listens on 127.0.0.1:27099 (only once a game is loaded) and
has no reply channel. So the chunk is wrapped: while it runs, print and MsgN
are captured, and afterwards its output, return values and any error are
written as JSON to garrysmod/data/gmod_lua/<run id>_<realm>.txt, which this
script polls for and then deletes.
"""
import argparse
import json
import socket
import sys
import time
import uuid
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

GMOD = Path.home() / (
    "Library/Application Support/CrossOver/Bottles/Steam/"
    "drive_c/Steam/steamapps/common/GarrysMod/garrysmod"
)
RESULTS = GMOD / "data" / "gmod_lua"
LUADEV = ("127.0.0.1", 27099)


class Realm(Enum):
    SERVER = "sv"
    CLIENT = "cl"
    SHARED = "sh"


@dataclass(frozen=True)
class RunResult:
    realm: Realm
    output: list[str]
    returns: list[str]
    error: str | None


class BridgeDown(Exception):
    pass


def long_string(code: str) -> str:
    level = 0
    while f"]{'=' * level}]" in code:
        level += 1
    eq = "=" * level
    return f"[{eq}[{code}]{eq}]"


def wrap(code: str, run_id: str) -> str:
    return f"""do
local realm = SERVER and "sv" or "cl"
local out = {{}}
local function capture(...)
  local parts = {{}}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  out[#out + 1] = table.concat(parts, "\\t")
end
local saved_print, saved_msgn = print, MsgN
local result = {{ output = out, returns = {{}} }}
local fn = CompileString({long_string(code)}, "gmod_lua", false)
if isstring(fn) then
  result.error = fn
else
  print, MsgN = capture, capture
  local r = {{ pcall(fn) }}
  print = saved_print
  MsgN = saved_msgn
  if r[1] then
    for i = 2, table.maxn(r) do result.returns[#result.returns + 1] = tostring(r[i]) end
  else
    result.error = tostring(r[2])
  end
end
file.CreateDir("gmod_lua")
file.Write("gmod_lua/{run_id}_" .. realm .. ".txt", util.TableToJSON(result))
end"""


def result_files(directory: Path, run_id: str, realm: Realm) -> list[Path]:
    realms = [Realm.SERVER, Realm.CLIENT] if realm is Realm.SHARED else [realm]
    return [directory / f"{run_id}_{r.value}.txt" for r in realms]


def collect_results(directory: Path, run_id: str, realm: Realm) -> list[RunResult]:
    results = []
    for path in result_files(directory, run_id, realm):
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        results.append(RunResult(
            Realm(path.stem.rsplit("_", 1)[1]),
            list(data.get("output") or []),
            list(data.get("returns") or []),
            data.get("error"),
        ))
    return results


def send(realm: Realm, code: str, label: str) -> None:
    try:
        with socket.create_connection(LUADEV, timeout=3) as s:
            s.sendall(f"{realm.value}\n{label}\n{code}".encode())
    except OSError as e:
        raise BridgeDown(f"luadev socket {LUADEV[0]}:{LUADEV[1]} not reachable ({e}); is a map loaded in GMod?") from e


def run(realm: Realm, code: str, timeout: float) -> list[RunResult]:
    run_id = uuid.uuid4().hex[:10]
    send(realm, wrap(code, run_id), "gmod_lua")
    expected = len(result_files(RESULTS, run_id, realm))
    deadline = time.monotonic() + timeout
    results = []
    while time.monotonic() < deadline:
        results = collect_results(RESULTS, run_id, realm)
        if len(results) >= expected:
            break
        time.sleep(0.2)
    for path in result_files(RESULTS, run_id, realm):
        path.unlink(missing_ok=True)
    return results


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("code", nargs="?")
    ap.add_argument("-f", "--file", type=Path)
    ap.add_argument("--realm", choices=[r.value for r in Realm], default="sv")
    ap.add_argument("--timeout", type=float, default=10)
    args = ap.parse_args()
    code = args.file.read_text() if args.file else args.code
    if code is None:
        ap.error("give code or --file")
    try:
        results = run(Realm(args.realm), code, args.timeout)
    except BridgeDown as e:
        print(f"bridge down: {e}", file=sys.stderr)
        return 2
    if not results:
        print("no result before the timeout (did the chunk hang, or is luadev refusing this player?)", file=sys.stderr)
        return 3
    failed = False
    for r in results:
        print(f"[{r.realm.value}]")
        for line in r.output:
            print(line)
        for value in r.returns:
            print(f"=> {value}")
        if r.error:
            print(f"ERROR {r.error}")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
