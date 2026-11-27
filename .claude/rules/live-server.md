# Rule: test and navigate on the live server

Two tools reach the running dev server. Use them instead of Bash loops over
RCON, and instead of guessing from the source what the game does.

- **The gmod MCP** (the gmod plugin's, from claude-config2's
  `plugins/gmod`, tools `mcp__plugin_gmod_gmod__*`). `lua_run` runs Lua on the server; `return` a value
  to see it. `rcon` runs console commands. `lua_errors`, `console_messages`,
  `console_log` and `game_events` read what happened. `breakpoint_set`,
  `breakpoint_hits`, `debug_state`, `debug_eval` and `debug_resume` debug.
  `watch_events` and `listeners` follow long-running work. Every tool takes
  `instance` (1 by default). From a shell, `dt gmod/mcp TOOL name=value ...`
  makes the same call, so several can be batched through `ctx_batch_execute`.
  What this repo's server runs is `.devtools/gmod.toml`.
- **The dev workbench** (`addons/sandcastle_dev`, loaded only on the dev
  server). Its library is indexed below. Each function returns a table: call
  it with `lua_run`. Each console command prints the same table as JSON:
  call it with `rcon`.

## To test a change

Pass the LuaJIT tests first (`.devtools/bin/check_lua.sh --changed`). Then, on the
server:

1. Load the change with `dev.reload({ files = { "addons/..." } })`, which
   keeps the game where it is. Never restart srcds. Change map only when
   the reload refuses a file, and say which file and why.
2. Read `lua_errors`, passing `since` to see only new ones.
3. Set up the situation from a saved scenario (`scenario_load NAME`,
   `dev_quickload`), not by hand. Save a new situation once with
   `scenario_save` or `dev_quicksave`.
4. Check the result as data: a `lua_run` that returns the values, plus
   `game_events` and `console_messages`. Don't judge from the console text.

## To find your way around the code

Ask the running game:

- `lua_run` with `return debug.getinfo(fn, "S").short_src` shows where a
  function was defined. `[C]` means a native twin.
- `breakpoint_set` in snapshot mode (the default) captures who reaches a
  line, with their locals, without stopping the server. Read the result
  with `breakpoint_hits`, then `breakpoint_clear`. Pause mode freezes the
  whole server, and clients time out after about 30 s: use it only when no
  one is playing.
- For a long-running command, `listeners` explains how to follow it to its
  end under the Monitor tool.

Lua sent to realm `cl` or `sh` reaches every client, but clients never
answer. If the server is down, and for luadev and Watch, use the gmod
plugin's `gmod-server` skill (this repo's own commands on it are the
`dedicated-server` skill). For the scenario format, migrations and limits,
use the `dev-workbench` skill.

## The dev library

Every `dev.*` function and console command the workbench has is indexed in
the `dev-workbench` skill (`.claude/skills/dev-workbench/SKILL.md`), which
`tests/dev_library_index_test.lua` holds to the workbench's code. Load the
skill before driving the workbench.
