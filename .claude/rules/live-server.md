# Rule: test and navigate on the live server

Two tools reach the running dev server. Use them instead of Bash loops over
RCON, and instead of guessing from the source what the game does.

- **The gmod MCP** (`.devtools/bin/gmod_mcp.py`, registered in `.mcp.json`,
  tools `mcp__gmod__*`). `lua_run` runs Lua on the server; `return` a value
  to see it. `rcon` runs console commands. `lua_errors`, `console_messages`,
  `console_log` and `game_events` read what happened. `breakpoint_set`,
  `breakpoint_hits`, `debug_state`, `debug_eval` and `debug_resume` debug.
  `watch_events` and `listeners` follow long-running work. Every tool takes
  `instance` (1 by default). From a shell, `dt gmod TOOL name=value ...`
  makes the same call, so several can be batched through `ctx_batch_execute`.
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
answer. If the server is down, use the `dedicated-server` skill. For the
scenario format, migrations and limits, use the `dev-workbench` skill; for
luadev and Watch, the `server-lua` skill.

## The dev library

`tests/dev_library_index_test.lua` holds this index to the workbench's code
in both directions. A new function or command needs a line here.

### Reload

| Function | Command | What |
|---|---|---|
| `dev.reload(opts)` | `dev_reload [cleanup]` | Capture the state, load the changed Lua again, restore the state; every step timed. `opts.files` names the files (repo or LUA paths) and skips the scan. `opts.cleanup` also cleans the map up first, and the result then lands in `dev.last_reload` a tick later. Refuses, with the reason: `ws/` and the gamemode's root files, `cl_` and `sh_` files (clients keep what they were sent), and files this map has not loaded |
| `dev.reload_plan()` | `dev_reload_plan` | The changed files a reload would take, and what it would do with each |
| `dev.reload_self()` | | Load the workbench's own files again |

### State

| Function | Command | What |
|---|---|---|
| `dev.capture()` | | The gameplay state as a versioned, JSON-ready table (`dev.SCHEMA`): mode, convars, rounds, points, flags, carts, map entities, players, soldiers |
| `dev.apply(state)` | | Restore a captured state in place; a report of what each section restored, and everything it could not |
| `dev.state(opts)` | `dev_state [verbose]` | A compact summary; `{ verbose = true }` gives the whole capture |
| `dev.diff(a, b)` | | The differences between two states |
| `dev.comparable(state)` | | A state as `dev.diff` compares it (soldiers as a sorted list, not by entity) |
| `dev.check_roundtrip()` | `dev_check_roundtrip` | Capture, apply, capture, diff |
| `dev.check_restore()` | `dev_check_restore` | Capture through JSON, disturb, apply, diff. Asynchronous: the result lands in `dev.last_check_restore` |

`dev.Refs` keys entities in a state: map entities by map creation id,
players by SteamID64.

### Scenarios

Scenarios are saved states, kept per map under `.devtools/scenarios/`.

| Function | Command | What |
|---|---|---|
| `dev.scenario.save(name, description)` | `scenario_save <name> [description]` | Save the current state under this map |
| `dev.scenario.load(name)` | `scenario_load <name>` | Restore one in place. Refuses another map's scenario, and a schema it cannot migrate |
| `dev.scenario.list(opts)` | `scenario_list [all]` | This map's scenarios; `{ all = true }` lists every map's |
| `dev.scenario.diff(a, b)` | `scenario_diff <a> <b>` | Two scenarios, or one against `"current"` |
| `dev.scenario.quicksave(slot)` | `dev_quicksave [slot]` | Save to a quick slot |
| `dev.scenario.quickload(slot)` | `dev_quickload [slot]` | Load a quick slot |

### The gamerules harness

The harness stands in for the map's gamerules. Turn it on with
`dev.harness.enable(true)` or the convar `dev_gamerules_harness 1`. While
it is on, it traces every input the map sends, and gameplay can be frozen,
stepped and set by hand. While it is off, everything that changes the game
refuses (`mode` and `release`, pausing and stepping, round state, timer
inputs, wins); `status`, `trace`, `timers` and the two proofs still work.

| Function | Command | What |
|---|---|---|
| `dev.harness.enable(on)` | | Turn the harness on or off |
| `dev.harness.status()` | `dev_harness_status` | A compact summary |
| `dev.harness.mode(mode, rules)` | `dev_harness_mode <forward\|intercept\|queue> [input action\|clear ...]` | What becomes of map inputs: forward them, drop them, or queue them; `rules` sets one input's action (`false` clears it) |
| `dev.harness.release()` | `dev_harness_release` | Forward the queued inputs |
| `dev.harness.trace(opts)` | `dev_harness_trace [since] [limit]` | The trace of inputs, effects and outputs; `{ since, kinds, limit }` |
| `dev.harness.pause()` | `dev_pause` | Freeze gameplay (time scale 0); the luadev socket still answers |
| `dev.harness.resume()` | `dev_resume` | Unfreeze gameplay |
| `dev.harness.step(n)` | `dev_step [ticks]` | Run n ticks, then freeze; returns at once |
| `dev.harness.set_round_state(state)` | `dev_round_state <state>` | Put the round in a state as a restore does, with no enter handler run. For the real path, use `force_win` or `restart_round` |
| `dev.harness.restart_round()` | | Restart the round through the rounds controller |
| `dev.harness.force_win(who)` | `dev_force_win red\|blue\|stalemate` | End the round, even with wins suppressed |
| `dev.harness.suppress_wins(on)` | `dev_suppress_wins 0\|1` | Drop, and trace, every win and stalemate, so the round runs on |
| `dev.harness.timers()` | | The round timers' names |
| `dev.harness.timer(name, input, value)` | `dev_timer <name\|-> <input> [value]` | Any `team_round_timer` input on a timer (the HUD's when the name is nil or `-`); returns the timer as it is after |
| `dev.harness.set_timer(seconds, name)` | `dev_timer_set <seconds> [name]` | Set a timer's time |
| `dev.harness.pause_timer(name)` | | Pause a timer |
| `dev.harness.resume_timer(name)` | | Resume a timer |
| `dev.harness.check_off()` | `dev_harness_check_off` | Prove the harness, off, left the gamerules as they were |
| `dev.harness.check_equivalence()` | `dev_harness_check_equivalence` | Prove map inputs do the same with the harness on and off |

### For the workbench's own code

| Function | What |
|---|---|
| `dev.Command(name, fn, help)` | A console command that runs `fn(args, ply)` and prints the table it returns as JSON, or the error |
| `dev.Fail(message)` | An error the caller can act on, raised at the caller's line |
| `dev.Allowed(ply)` | Who may use the workbench: the console, RCON or a superadmin |
| `dev.Describe(ent)` | An entity as text a trace can hold: class, index and name |
| `dev.Rounds()` | The rounds controller; refuses when the gamemode is not up |
| `dev.WhenReady(id, fn)` | Run fn once the gamemode and the map's entities are up |
| `dev.load(path, ...)` | Run a file of the workbench's `lua/` folder (the dev server's mount defines it) |
| `dev.require(name)` | Load a workbench module from `lua/includes/modules/` once |
