---
name: server-lua
description: Run Lua on Sandcastle's dedicated server and read its output, return values and errors directly, through luadev's socket (server_lua.py), and have the server push events back when a condition is met or times out (Watch, server_watch.py). Use whenever you'd otherwise send `lua_run` over RCON or poll the server from a bash loop — to inspect server state, call a function, test a snippet, run a Lua file, or wait for something to happen in game.
---

# Running Lua on the dedicated server

```bash
dt lua 'return #player.GetAll(), engine.TickCount()'
dt lua --realm cl 'print("on every client")'
dt lua --realm sh 'return SERVER'
dt lua --instance 2 'return game.GetMap()'   # a second server (srcds.py --instance 2)
```

For anything past one line, send the chunk on stdin with a quoted heredoc:
no shell quoting at all, and no file to write.

```bash
dt lua --instance 2 <<'LUA'
local train = easylua.FindEntity("minecart_tracktrain")
return train:GetPos(), train:GetInternalVariable("m_flSpeed")
LUA
```

The chunk comes from the argument, else `-f FILE`, else stdin (also for `-`).

What comes back: each `print`/`MsgN` line, then each return value as
`=> value`, then `ERROR <message>` for a runtime or syntax error. For `cl`
and `sh` you also get `(sent to N clients)`. Clients never reply, so a
`cl` chunk's output goes only to their consoles.

| Exit | Meaning |
|------|---------|
| 0 | ran |
| 1 | Lua error (shown after `ERROR`) |
| 2 | bridge down: no server listening on the instance's port (127.0.0.1:27098 for the main one) |
| 3 | no reply before `--timeout` (default 10 s), or the connection closed without one |

## Never

- **Don't run `srcds.py rcon 'lua_run ...'`.** Its output only reaches the
  logs, RCON quoting mangles code, and a long chunk doesn't fit. RCON is
  still right for console commands (`changelevel`, `status`, convars).
- **Don't point `gmod_lua.py` at the server.** It drives the game the
  operator is playing (port 27099), not the dedicated server.

## Writing chunks

- Prefer `return` to `print` for values: you get `=> value` lines.
- Use a heredoc (`<<'LUA'`, quoted so the shell leaves `$` and quotes alone)
  for anything longer than a line. `-f` is for a chunk you keep.
- luadev's `easylua` is loaded. `easylua.FindEntity("minecart_tracktrain")`
  finds a map entity by its targetname. `me`, `this` and `there` are only set
  when a player runs code, so they are nil in these chunks.
- Globals a chunk defines stay for later chunks until the map changes. Keep
  helpers (a snapshot function, say) in one chunk and call them from others.
- A chunk runs inside the server's Think. Something that loops or blocks
  stalls the server until `--timeout`, so keep chunks short.
- `print` output also still reaches the console log as usual.

## Waiting for something in game: Watch

Don't poll the server from a bash loop. Have the server push events instead.
`server_root/sandcastle_watch.lua` is a server autorun that defines a global
`Watch`. Set its watches up with a chunk, then follow them with
`server_watch.py`:

| Call | Pushes |
|------|--------|
| `Watch.Emit(name, text)` | one `event` |
| `Watch.Every(name, seconds, fn)` | `changed` with fn's answer, each time it changes |
| `Watch.Until(name, seconds, timeout, check)` | `met` with the report once `check()` returns `true, report`; `timeout` with the last report after `timeout` seconds |
| `Watch.On(hookName, name, fn)` | `event` with `fn(...)`'s answer each time the hook runs |
| `Watch.Stop(name)` | ends a watch; starting one again under its name replaces it |

A function that errors pushes `error` and its watch stops, so a broken check
never looks like a quiet wait. Each event is a line `<CurTime> <name> <kind>
<text>` in the instance's `data/sandcastle_watch.txt`.

```bash
dt lua --instance 2 <<'LUA'
Watch.On("WSMiniRoundStart", "stage", function(round) return round:GetName() end)
Watch.Until("stage3", 1, 360, function()
	local round = WS.Feature("capture"):CurrentRound()
	return IsValid(round) and round:GetName() == "round_c", tostring(round)
end)
LUA
```

Then follow them:

- **Every event, under the Monitor tool:** `dt watch --instance 2 --until stage3`.
  Each line is a notification, and the stream ends with the wait.
- **One answer:** run the same command as a background Bash. It exits 0 when
  the wait is met and 1 on its timeout or error.

It prints only events written after it starts, so arm the watches first, or
start following just before the moment you're waiting for. To drive the
game while you wait, a chunk's `timer.Create` loop can play the part of a
player or an admin, as in a test.

## Big results: through context-mode

The gmod MCP tools answer straight into the conversation. For a result you
will search rather than read (a long console log, every Lua error with its
stack, the game event ring), run the same tool from the command line under
`ctx_batch_execute`, so the text is indexed and only what your queries match
comes back:

```
ctx_batch_execute(commands=[
  {label: "gmod lua_errors",  command: "dt gmod lua_errors"},
  {label: "gmod console_log", command: "dt gmod console_log lines=2000"},
  {label: "gmod game_events", command: "dt gmod game_events name=round_win"}],
  queries=["attempt to index nil", "round_win team"])
```

`call TOOL name=value ...` takes the tool's arguments (integers and booleans
as JSON, the rest as text, so `code=return 1` needs quoting as one shell
word) and prints its text, exiting 1 if it failed. Later questions go to
`ctx_search(source: "gmod ...")`.

## How it works

`server_root.py` adds `server_root/luadev_socket.lua` as a server autorun,
and links luadev's win64 LuaSocket into the server's own `lua/bin` as
`gmsv_luasocket_win64.dll`. The autorun listens on 127.0.0.1:27098 (instance
*n*: 27098 + 2·(n−1), which skips the game's 27099; the build writes the port
into the root's `data/`) and runs
each chunk with `luadev.RunOnServer` / `RunOnClients`, capturing `print`
and `MsgN`. It answers with JSON on the same connection. The protocol is
in `server_lua.py`'s docstring.

## When it says bridge down

1. Is the server up? `dt rcon status`. If not,
   start it (see `dedicated-server`).
2. Was the server started before this listener existed? A server that is
   already running loads it once, without a restart:
   `python3 .devtools/bin/server_root.py`, then
   `dt rcon 'lua_openscript autorun/server/luadev_socket.lua'`.
   Every map change after that loads it by itself.
3. If it still fails, read the end of `.devtools/artifacts/srcds.log` for a
   `luadev_socket` error.
