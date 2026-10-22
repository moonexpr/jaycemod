---
name: dev-workbench
description: Sandcastle's dev workbench on the dedicated server — reload changed gamemode Lua while keeping the game state (dev_reload), save and load gameplay scenarios (scenario_save/load, quicksave), capture and restore state, freeze or step gameplay, and trace or intercept the map's gamerules I/O (dev_gamerules_harness). Use whenever you would otherwise change map to try a Lua change, rebuild a test situation by hand, or wait for a round to reach a state; reach for it before changelevel.
---

# Dev workbench

`addons/sandcastle_dev`, loaded only on the dev server (the mount
`.devtools/bin/server_root/sandcastle_dev.lua` sets `DEBUG` and loads it on
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

## Commands

| Function | Command | What |
|---|---|---|
| `dev.state()`, `dev.state({ verbose = true })` | `dev_state [verbose]` | Compact summary (map, round, timer, scores, points, flags, soldiers, players), or the full capture |
| `dev.capture()` / `dev.apply(state)` | — | The state as a plain table / put back in place; apply refuses another map's or schema's |
| `dev.check_roundtrip()` | `dev_check_roundtrip` | capture, apply, capture, diff: `ok`, `differences` |
| `dev.check_restore()` | `dev_check_restore` | capture through JSON, disturb every section, apply, diff; result in `dev.last_check_restore` a tick later |
| `dev.diff(a, b)` | — | Differences of two states (soldiers compared by what they are) |
| `dev.reload(opts)` | `dev_reload [cleanup] [files...]` | Load changed Lua again, keeping the state; `{ cleanup = true }` also remakes the map's entities (result in `dev.last_reload`) |
| `dev.reload_plan()` | `dev_reload_plan` | The changed files a reload would take, and what it would do |
| `dev.scenario.save(name, description)` | `scenario_save <name> [description]` | Save under this map |
| `dev.scenario.load(name)` | `scenario_load <name>` | Restore in place (report as `dev.apply`'s) |
| `dev.scenario.list({ all = true })` | `scenario_list [all]` | This map's (or every map's) scenarios, newest first |
| `dev.scenario.diff(a, b)` | `scenario_diff <a> <b>` | Names, or `current` for the live state |
| `dev.scenario.quicksave(slot)` / `quickload(slot)` | `dev_quicksave [n]`, `dev_quickload [n]` | Slot 1 by default |
| `dev.harness.enable(true)` | `dev_gamerules_harness 1` | A `dev_tf_gamerules` takes the gamerules' name (real ones become `<name>__real`) |
| `dev.harness.mode(m, rules)` | `dev_harness_mode <forward\|intercept\|queue> [input action ...]` | What becomes of the map's inputs; per-input rules |
| `dev.harness.release()` | `dev_harness_release` | Forward the queued inputs |
| `dev.harness.trace({ since, kinds, limit })` | `dev_harness_trace [since] [limit]` | Inputs, round effects, outputs, wins, notes |
| `dev.harness.pause()` / `resume()` / `step(n)` | `dev_pause`, `dev_resume`, `dev_step [n]` | Freeze gameplay (time scale 0), run n ticks |
| `dev.harness.set_round_state(s)` | `dev_round_state <name\|n>` | As a restore does: no enter handler runs |
| `dev.harness.timer(name, input, value)`, `set_timer(s, name)` | `dev_timer`, `dev_timer_set` | Any team_round_timer input; a disabled timer is refused |
| `dev.harness.force_win(who)` / `suppress_wins(on)` | `dev_force_win`, `dev_suppress_wins` | red, blue, stalemate / drop every win asked for |
| `dev.harness.check_off()` / `check_equivalence()` | `dev_harness_check_off`, `dev_harness_check_equivalence` | Proof the harness off changes nothing, and that map inputs act the same through it |

Harness controls need the harness on. While frozen the MCP still answers,
about 1.3 s a call (the server thinks about once a second).

## Scenario format

`.devtools/scenarios/<map>/<name>.json` (the server writes it through
`data/sandcastle_dev/scenarios`, linked by `server_root.py`; `quick_*` files
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
