---
name: dedicated-server
description: Run, drive and stop Sandcastle's Garry's Mod dedicated server under CrossOver (srcds.py, RCON, luadev, lua_watch, in-game checks, a test client). Use when asked to start or restart the server, change its map, run console commands or Lua on it, read its console log, push live Lua edits to it, run the in-game checks, or connect a GMod client to it.
---

# Dedicated server

Every tool is in `.devtools/bin/` and documents itself in its module
docstring; read that before changing how you use one. Run them from the
repo root with `python3`.

## Never

- **Never run a server in the CrossOver bottle "Team Fortress 2".** The
  operator plays there, and a server in that bottle once killed their game.
  Servers run only in the bottle "Steam" (`srcds.py`'s `BOTTLE`, which
  refuses any other). Don't launch `srcds_win64.exe` or wine by hand.
- **Never kill wine processes by name or pattern** (`pkill wine`,
  `killall`, `wineserver -k`, `wineboot`). `srcds.py stop` signals only the
  processes it recorded in `.devtools/artifacts/srcds.pid`.
- **Never start the GMod client** except through `gmod_client.py`, which
  refuses while TF2 or another GMod runs and closes its client if the
  operator's game starts.
- Don't use port 27015: it belongs to the operator's own game. The server
  uses 27025.

## Start, command, stop

```bash
python3 .devtools/bin/srcds.py start --map pl_upward      # waits until the map is up
python3 .devtools/bin/srcds.py rcon 'status'              # any console command
python3 .devtools/bin/srcds.py rcon 'changelevel koth_viaduct'
python3 .devtools/bin/srcds.py stop
python3 .devtools/bin/srcds.py console                    # follow the console, in color, in iTerm
```

`start` takes `--map` (default `gm_construct`), `--port` (27025),
`--maxplayers`, `--ip` (127.0.0.1, so RCON stays on this machine) and
`--no-lua-refresh` (adds `-disableluarefresh`) and `--console` (opens the
iTerm window, profile "Dark", that `console` opens). It first builds the
server's own GMod root (`server_root.py`). The server runs the gamemode
that the shared install's `garrysmod/gamemodes/sandcastle` points to, which
is the main checkout, not a worktree. Workshop addons (DrGBase), luadev
access on LAN and ULX's luadev commands come from `server_root/`'s autorun.

Useful after a map loads:

- `wetsand_defaults_apply` puts every loaded Sandcastle convar back to its
  default (`addon/cfg/sandcastle_defaults.cfg`; `exec` can't read an
  addon's cfg).
- `mp_aiwar_start` / `mp_aiwar_end` start and end the AI war. The war's
  admin and NextSoldier commands (`ns_*_print`, `mp_aiwar_slots_print`)
  print to the server console.

## Logs and artifacts

| What | Where |
|------|-------|
| Everything the console printed, as the supervisor read it | `.devtools/artifacts/srcds.log` |
| The server's `-condebug` log | `garrysmod/console.log` in the server root (`server_root.py` prints where it is) |
| The RCON password | `.devtools/artifacts/rcon_password` |
| The processes `start` launched | `.devtools/artifacts/srcds.pid` |

Read logs with `tail` or a filtering command, not whole: they grow long.

## Running Lua

- On the dedicated server, use `server_lua.py` (see the `server-lua`
  skill): `python3 .devtools/bin/server_lua.py 'print(game.GetMap())'`.
  It runs the chunk through luadev and prints its output and return values.
  Don't use `srcds.py rcon 'lua_run ...'`: its output only reaches the logs.
- `gmod_lua.py` is **not** for the dedicated server. It runs Lua in the
  game the operator is playing, through luadev's socket on 127.0.0.1:27099,
  and reads its results from the shared install's `data/`. The server's
  `data/` is its own.

## Live Lua edits

GMod's Lua auto refresh never fires under CrossOver on macOS. Keep the
watcher running in the background while editing:

```bash
python3 .devtools/bin/lua_watch.py      # run_in_background
```

It sends `lua_refresh_file` for each edited `.lua` file to the server (and
to a game the operator is playing). A **new** file only loads on the next
map change: `srcds.py rcon 'changelevel <map>'`. Remember, too, that each
map loads only the systems its entities pull in.

## In-game checks

```bash
python3 .devtools/bin/ingame_tests.py --maps koth_viaduct   # starts and stops its own server
python3 .devtools/bin/ingame_one.py <check>                  # one check on the server already running
```

The checks are `.devtools/bin/ingame/checks/<name>.lua`. `ingame_tests.py`
writes `.devtools/artifacts/ingame-report-<date>.md`. Run the LuaJIT suite
first (`.devtools/bin/run_lua_tests.sh`): it is faster and catches most
things.

## A client on the server

```bash
python3 .devtools/bin/gmod_client.py check                  # exit 0: a launch is allowed
python3 .devtools/bin/gmod_client.py start --minutes 20     # connects to 127.0.0.1:27025
python3 .devtools/bin/gmod_client.py stop
```

If `check` refuses, tell the operator why and stop there. Don't work around
it.

## When it goes wrong

- **`start` times out:** read the end of `srcds.log`. The server needs a
  terminal for stdin (the supervisor gives it a pty), and it crashes while
  mounting the Workshop unless it runs `-insecure -noworkshop -nosteam`,
  which `srcds.py` always passes.
- **`stop` leaves something running:** report it to the operator. Don't
  widen the kill.
- **A Wine console window opens (raw ANSI codes):** the server root's
  `srcds_win64.exe` should be `server_root.py`'s console-program copy, not a
  link. Run `server_root.py` and start again.
