---
name: dedicated-server
description: This repo's own side of its Garry's Mod dedicated server — what .workbench/gmod.toml mounts, the Sandcastle and AI-war console commands, ULX's luadev chat commands, the navigation benches, the Linux builds of the native modules, and the in-game checks. Use with the gmod plugin's gmod-server skill (which starts, stops and drives any project's server: srcds, RCON, luadev, Watch, the MCP) when the work is Sandcastle's or Wetsands'.
---

# This repo's dedicated server

The tools are the gmod plugin's (claude-config2's `plugins/gmod`): read its
`gmod-server` skill for starting, stopping, RCON, Lua, Watch, benches' leases,
added maps and live edits. Every `dt gmod/...` command run in this repo builds
and drives the server `.workbench/gmod.toml` describes.

## What the server runs

`.workbench/gmod.toml`: the `sandcastle` gamemode (the shared install's
`garrysmod/gamemodes/sandcastle`, which points to the main checkout; a worktree's
runs with `GMOD_GAMEMODE_DIR` naming its folder), the repo's addons
(foundation, NextSoldier, wartactics, the CS:S weapons, Model Viewer, the dev
workbench, ULX luadev), the workbench's scenarios as `data/sandcastle_dev/scenarios`,
this repo's server Lua (`.workbench/server_lua/`: `hotswap.lua`, and
`sandcastle_dev.lua`, which sets `DEBUG` and loads the workbench), the Workshop
addons and the map pool, the hostages' voice pack, the native modules once
built, and TF2's sound scripts. A map that stays after `dt gmod/add-map` moves
to its `[maps]`. Club Random runs on the same instances with its own config:
a start from one project takes away what the other linked.

## Useful after a map loads

- `ws_defaults_apply` puts every loaded Sandcastle convar back to its default
  (`addons/sandcastle/cfg/sandcastle_defaults.cfg`; `exec` can't read an addon's cfg).
- `mp_aiwar_start` / `mp_aiwar_end` start and end the AI war. The war's admin
  and NextSoldier commands (`ns_*_print`, `mp_aiwar_slots_print`) print to the
  server console.
- To keep the server on one map: `mp_timelimit 0; mp_winlimit 0; mp_maxrounds 0`
  (CLAUDE.md), again after any `changelevel`.

## ULX's luadev commands

`addons/ulx_luadev`, its own repository (github.com/moonexpr/ulx_luadev), checked
out here and untracked. A run on the server answers its caller in chat and with a
sound cue; each caller tunes them on its own client with
`cl_luadev_output_maxlines` (1; 0: none), `_maxchars` (120; 0: uncut), `_timeout`
(10 s) and the sounds `_success`, `_error`, `_progress`, `_neutral` (empty:
silent). Beside luadev's chat commands it gives `!lfile`, `!lent`, `!lwep`,
`!leffect`, `!lwatch`, `!lunwatch`, `!lcopy` and `!lspawn`. `!print this` (or
`we`, `there`, `trace`, `me`...) also shows its caller a box and lines describing
each entity (an NPC's activity, animation, target and schedule; a NextSoldier's
behaviour and group stacks) for its `cl_luadev_output_overlay` seconds.

## Benches and trials: `.workbench/experiments/`

Each experiment is a folder with its scripts, a README stating its question and
status, and its results in `results/` (ignored by git): the AI war's benches,
the foundation bench, dev_3house's room operations, the navigation benches, the
dustbowl stage-2 bench, the stranding A/B, the hostage survey, the route
records, and the in-game checks. The navigation benches: `ns-bench/ns_bench_map.py`
builds a bench map (a region of a shipped map, decompiled with BSPSource and
cordoned off with hammer-mcp), and `ns-bench/ns_bench_run.py <bench>` runs its
errands on a server leased from the plugin's `InstanceManager`.

## The Linux server's native modules

Before `dt gmod/srcds start --runtime docker`, build the repo's modules for
Linux (once, and after a change to a crate): `python3 .workbench/bin/native_linux.py`
(each crate's `target/x86_64-unknown-linux-gnu/release/`, which `gmod.toml`'s
`[native.linux64]` links). NextSoldier's engine binding does not run there yet
(`nextsoldier.engine.refused` says why: it reads win64's `server.dll`).

## In-game checks

```bash
python3 .workbench/experiments/ingame/ingame_tests.py --maps koth_viaduct   # starts and stops its own server
python3 .workbench/experiments/ingame/ingame_one.py <check>                  # one check on the server already running
```

The checks are `.workbench/experiments/ingame/ingame/checks/<name>.lua`; `ingame_tests.py`
writes `results/ingame-report-<date>.md` beside it. Run the LuaJIT suites of
what changed first (`.workbench/bin/check/check_lua.sh --changed`): it is faster and
catches most things.

## Live Lua edits

`dt gmod/lua-watch` refreshes edited files of `addons/sandcastle`. It does
nothing for foundation modules and feature parts (they are compiled, not
included): for those, and to keep the game where it is, use the dev
workbench's `dev.reload` (the `dev-workbench` skill).
