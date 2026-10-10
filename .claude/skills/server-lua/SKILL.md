---
name: server-lua
description: Run Lua on Sandcastle's dedicated server and read its output, return values and errors directly, through luadev's socket (server_lua.py). Use whenever you'd otherwise send `lua_run` over RCON — to inspect server state, call a function, test a snippet, or run a Lua file on the running server or its clients.
---

# Running Lua on the dedicated server

```bash
python3 .devtools/bin/server_lua.py 'print(game.GetMap())'
python3 .devtools/bin/server_lua.py 'return #player.GetAll(), engine.TickCount()'
python3 .devtools/bin/server_lua.py -f path/to/chunk.lua
python3 .devtools/bin/server_lua.py --realm cl 'print("on every client")'
python3 .devtools/bin/server_lua.py --realm sh 'return SERVER'
```

What comes back: each `print`/`MsgN` line, then each return value as
`=> value`, then `ERROR <message>` for a runtime or syntax error. For `cl`
and `sh` you also get `(sent to N clients)`. Clients never reply, so a
`cl` chunk's output goes only to their consoles.

| Exit | Meaning |
|------|---------|
| 0 | ran |
| 1 | Lua error (shown after `ERROR`) |
| 2 | bridge down: no server listening on 127.0.0.1:27098 |
| 3 | no reply before `--timeout` (default 10 s), or the connection closed without one |

## Never

- **Don't run `srcds.py rcon 'lua_run ...'`.** Its output only reaches the
  logs, RCON quoting mangles code, and a long chunk doesn't fit. RCON is
  still right for console commands (`changelevel`, `status`, convars).
- **Don't point `gmod_lua.py` at the server.** It drives the game the
  operator is playing (port 27099), not the dedicated server.

## Writing chunks

- Prefer `return` to `print` for values: you get `=> value` lines.
- Use `-f` for anything longer than a line or with tricky quoting. Put
  throwaway chunk files in the session scratchpad.
- A chunk runs inside the server's Think. Something that loops or blocks
  stalls the server until `--timeout`, so keep chunks short.
- `print` output also still reaches the console log as usual.

## How it works

`server_root.py` adds `server_root/luadev_socket.lua` as a server autorun,
and links luadev's win64 LuaSocket into the server's own `lua/bin` as
`gmsv_luasocket_win64.dll`. The autorun listens on 127.0.0.1:27098 and runs
each chunk with `luadev.RunOnServer` / `RunOnClients`, capturing `print`
and `MsgN`. It answers with JSON on the same connection. The protocol is
in `server_lua.py`'s docstring.

## When it says bridge down

1. Is the server up? `python3 .devtools/bin/srcds.py rcon status`. If not,
   start it (see `dedicated-server`).
2. Was the server started before this listener existed? A server that is
   already running loads it once, without a restart:
   `python3 .devtools/bin/server_root.py`, then
   `python3 .devtools/bin/srcds.py rcon 'lua_openscript autorun/server/luadev_socket.lua'`.
   Every map change after that loads it by itself.
3. If it still fails, read the end of `.devtools/artifacts/srcds.log` for a
   `luadev_socket` error.
