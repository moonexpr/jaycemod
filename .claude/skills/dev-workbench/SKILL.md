---
name: dev-workbench
description: Sandcastle's dev workbench on the dedicated server — reload changed gamemode Lua while keeping the game state (dev_reload), save and load gameplay scenarios (scenario_save/load, quicksave), capture and restore state, freeze or step gameplay, and trace or intercept the map's gamerules I/O (dev_gamerules_harness). Use whenever you would otherwise change map to try a Lua change, rebuild a test situation by hand, or wait for a round to reach a state; reach for it before changelevel.
---

# Dev workbench

`addons/sandcastle_dev`, loaded only on the dev server (the mount
`.workbench/server_lua/sandcastle_dev.lua` sets `DEBUG` and loads it on
every map). Every command is a `dev.*` Lua function that returns a table;
the console commands print the same table as JSON. Drive it through the
gmod MCP (`lua_run` for the functions, `rcon` for the commands). Errors
say what to do; nothing is skipped without being reported.

## The loop

1. Get the game to the situation once, then `dev.scenario.save("name", "what it is")`
   (or `dev.scenario.quicksave()`).
2. Edit Lua.
3. `dev.reload({ files = { "<repo path>", ... } })`: the named files load
   again and the state comes back (about 20 ms). With no `files` it finds the
   changed ones itself (about 0.4 s: it reads every file's time). Read the
   result: `reloaded`, `refused` (with why), `apply.missing`, `apply.notes`.
4. Probe. To go back to the saved situation: `dev.scenario.load("name")`.

Reach for `changelevel` only when `dev.reload` refuses a file (below) or a
new file must load. A changelevel plus a scenario load restores the game in
about 9 s on cp_altitude; a reload, in 20 ms to 1 s.

## The dev library

`tests/dev_library_index_test.lua` holds this index to the workbench's code
in both directions. A new function or command needs a line here.

### Reload

| Function | Command | What |
|---|---|---|
| `dev.reload(opts)` | `dev_reload [cleanup]` | Capture the state, load the changed Lua again, restore the state; every step timed. `opts.files` names the files (repo or LUA paths) and skips the scan. `opts.cleanup` also cleans the map up first, and the result then lands in `dev.last_reload` a tick later. A shared entity's new code reaches the clients too. Refuses, with the reason: `ws/` and the gamemode's root files, `cl_` and `sh_` files (clients keep what they were sent), and files this map has not loaded: `dev.run` runs those by hand |
| `dev.reload_plan()` | `dev_reload_plan` | The changed files a reload would take, and what it would do with each |
| `dev.reload_self()` | | Load the workbench's own files again |
| `dev.run(file, realm)` | `dev_run <file> [sv\|cl\|sh]` | Run a Lua file again now, as it is on disk, where `dev.reload` refuses it (a root `sh_` file, a feature's `cl.lua`, a new file): on the server, every client (through luadev) or both, by its name unless `realm` is given. It runs as the gamemode ran it (`GM` the gamemode); an entity's or weapon's own file is registered again. A root file's state starts over; clients joining later get the file as the map loaded it |
| `dev.run_entity_on_clients(file)` | | `dev.reload`'s: a shared entity's new code to every client, which registered the old one |

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

Scenarios are saved states, kept per map under `.workbench/scenarios/`.

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

### VProf (HolyLib)

The engine's own profiler, read as data through [HolyLib](https://github.com/RaphaelIT7/gmod-holylib#vprof)'s
`vprof` library: the server thread's time by budget group and by scope, the engine's C++ (NextBots,
physics, networking) beside the Lua (`GMOD`: `CLuaGamemode::Call (<hook>)`, `CScriptedEntity::Call
(...)`). It names the time the LuaJIT sampler charges to the hook dispatcher. Needs HolyLib on the
server: `dt gmod/srcds start --runtime docker --holylib` after `dt gmod/holylib fetch` (the
`gmod-server` skill); without it each refuses. Times are ms; per frame is per tick.
The `profile_server` probe's `WSProfile.Start(s, scope, { vprof = true })` puts each wrapped
function in a scope of its own (group `WSProfile`), so they land in the same tree.

| Function | Command | What |
|---|---|---|
| `dev.vprof.status()` | `dev_vprof_status` | Loaded, running, frames and ms sampled, the last and peak frame, `holylib_vprof_*` convars |
| `dev.vprof.start(opts)` | `dev_vprof_start [scripts] [keep]` | Start VProf, reset first unless `keep`; `scripts` sets `holylib_vprof_trackscripts`: a scope for every script GMod calls into |
| `dev.vprof.stop(opts)` | `dev_vprof_stop [rows] [tree]` | Stop it and return the report |
| `dev.vprof.report(opts)` | `dev_vprof_report [rows] [tree]` | Self time by budget group, then the top scopes (merged by name: calls, total, self, peak, per frame); `{ rows, limit, tree, text }` |
| `dev.vprof.reset()` | `dev_vprof_reset` | Forget what it sampled, and the peaks |
| `dev.vprof.counters()` | `dev_vprof_counters` | VProf's counters by name |
| `dev.vprof.window(seconds, opts)` | `dev_vprof_window <seconds> [rows] [scripts] [sample]` | VProf over a window from nothing; `sample` runs the LuaJIT sampler (wsprofile) over the same window. Asynchronous: the report lands in `dev.last_vprof` (`lua` the sampler's) |
| `dev.vprof.cancel()` | `dev_vprof_cancel` | End a window early, stopping what it started |

### Probes

Lua that asks the running game one question and answers it as data, in
`sandcastle_dev/probes/<name>.lua`, read from disk each time it runs (an edit needs no reload);
its first comment line says what it asks.

| Function | Command | What |
|---|---|---|
| `dev.probe(name, ...)` | `dev_probe <name>` | Run a probe with the arguments given; what it returns (a probe that defines a global, as `profile_server`'s `WSProfile`, returns nothing: call the global next) |
| `dev.probes()` | `dev_probes` | Every probe, `{ name, about }` |

The probes: the AI war's costs (`aiwar_look_probe`, `aiwar_tick_probe`, `aiwar_tree_probe`), its
bots and rounds (`bot_probe`, `bot_status`, `war_round_check`, `lane_audit`, `stuck_census` then
`stuck_report`), MvM's bomb carrier (`ctfbot_check`, `ctfbot_demo`), the engineers' defence
(`engineer_defense`), the Path Follower stool's modes (`squad_member_check`,
`tactical_behavior_check`), NextSoldier on the engine (`next_soldier_head_check`,
`next_soldier_round_check`, `nextsoldier_components_check`, `nextsoldier_engine_check`), the nav
mesh and its searches (`nav_reach`, `navsearch_live_check`), what hotswap would list
(`hotswap_listing`) and the function profiler (`profile_server`). `dev_probes` says what each asks.

### Entities

| Function | Command | What |
|---|---|---|
| `PLAYER:AddCondition(cond, timeout)` | | Put a player in a TF2 condition (`WS.AddCondition`) for `timeout` seconds, -1 (the default) for good; `cond` its number or name (`URINE`, `TF_COND_URINE`), an unknown one refused |
| `PLAYER:RemoveCondition(cond)` | | Take a condition away (`WS.RemoveCondition`), by number or name |
| `ENTITY:Teleport(target, facingTowards)` | | Put an entity before `target`, along the way it faces, the two clear of each other; turned to face it (`facingTowards`, true unless false) or the way it faces. Its hull is swept out from `target`, so a wall stops it short; its motion is stopped. Returns where it stands and its yaw |

### easylua

Players by team, made as easylua makes `all` (`CreateAllFunction`): called, each gives its team's
players now; a method called on one runs on each of them (`RED:AddCondition("URINE", 5)`).

| Global | What |
|---|---|
| `RED` | RED's players |
| `BLU` | BLU's players |
| `SPEC` | The spectators |

### ULX

The workbench's ULX commands (`lua/ulx/modules/sh/sandcastle_dev.lua`), in chat or the console:

| Chat | What |
|---|---|
| `!thirdperson`, `!firstperson` | The caller's view from behind them, to see their own model; anyone may |
| `!give <players> <class>` | A weapon to each player (the spawn menu's weapons complete); admins |

`!print` of a NextSoldier (ulx_luadev's overlay) adds its `behavior:` and `group:` stacks, through
the `ULXLuaDevDescribe` hook the workbench answers.

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

## Scenario format

`.workbench/scenarios/<map>/<name>.json` (the server writes it through
`data/sandcastle_dev/scenarios`, linked by `gmod.toml`'s `[data]`; `quick_*` files
are gitignored). Fields: `format`, `name` (a-z, 0-9, `_`, `-`),
`description`, `map`, `schema`, `saved_at`, `state`. `state.sections`:
`convars`, `rounds`, `capture`, `flag`, `payload`, `toggles`, `players`,
`aiwar` (a section is absent when the map has nothing of it). Times are
seconds from the capture. A scenario of another map is refused with the
changelevel to make; an older schema migrates (`MIGRATIONS` in
`sv_scenarios.lua`, one function a step); a newer one is refused. Raise
`SCHEMA` in `sv_state.lua` and add a migration when a section's shape
changes.

## What reload refuses or cannot do

- `ws/` files and the gamemode's root files: changelevel (GMod's own
  refresh would run the whole gamemode again).
- `cl_`/`sh_` files: clients keep what they were sent; changelevel.
- New files, new network strings, precache, new client files: changelevel.
- A feature's top-level locals start again (caches, the flag's carry bones);
  state that lives only in a local is lost.
- A field deleted from an entity file stays until the map changes (the
  registration merges); `Initialize` does not run again without `cleanup`.

## Known limits of capture and restore

- A payload cart comes back to the last path node it passed.
- A soldier that died is made again: a new entity under a new key, its
  enemy, path and fire team fresh; the war may give roles out again.
- An AI war not started yet (a map just loaded) cannot take soldiers: the
  load says so; load again once the game is in Gameplay.
- Who stands in a capture area follows the players, not the scenario.
- Players are matched by SteamID64 (bots by name); weapon clips refill.
- Ammo and other name-keyed lists are lists: JSON turns a key like `357`
  back into a number.
- Disturbing a game for a test: never hand one team every point (a real
  win, whose outputs and cleanup no restore undoes); `check_restore` avoids it.
