# Sandcastle pass 2: working contract

Sandcastle is a Garry's Mod gamemode: Sandbox, plus working TF2 gameplay
entities, so TF2 maps (pl_, plr_) play their rounds. Pass 1 made one pl round
work on pl_badwater. Pass 2 brings the entities to roughly 75% of TF2's
behaviour, adds a team switcher, and adds payload race (plr_). Four agents
work in parallel, each in its own git worktree and branch; the integrator
(the parent session) merges and tests in game.

## Layout

```
addons/sandcastle/gamemodes/sandcastle/
  sandcastle.txt                 gamemode manifest (base: sandbox)
  gamemode/shared.lua            GM, DeriveGamemode("sandbox"), module loader, CreateTeams, StartCommand
  gamemode/init.lua              server GM overrides (spawn, death, team default); sends every foundation/ file to clients
  gamemode/cl_init.lua           client GM overrides (HUDPaint -> hook "SandcastleHUDPaint")
  gamemode/ws/sh_*.lua      loaded on both realms (sh_core first, then name order)
  gamemode/ws/sv_*.lua      loaded on the server, name order
  gamemode/ws/cl_*.lua      loaded on clients, name order
  gamemode/foundation/<system>.lua         a game system's pure logic (teams, spawn, players, rounds,
                                           payload, capture, spectate): module foundation.<system>
  gamemode/foundation/<system>/<part>.lua  a part of that system: module foundation.<system>.<part>,
                                           which module() nests in the system's table, so a part's
                                           name must not be a name the system defines
                                 Each is a plain module(...) (no package.seeall, so no GMod globals;
                                 standard-library globals and other foundation modules, via
                                 require("foundation.<name>"), captured as locals above the call), and
                                 game-specific values (TF2's team numbers) are data of the system
                                 that owns them. NOT auto-loaded: the module that uses it loads it
                                 with WS.require("foundation.<system>") (sh_core.lua)
  entities/entities/<class>.lua  one file per TF2 entity class
tests/harness.lua, tests/*_test.lua   LuaJIT tests for foundation modules, loaded with T.require (.devtools/bin/run_lua_tests.sh)
```

New modules need no wiring: drop a correctly prefixed file into gamemode/ws/, or a module(...) file into gamemode/foundation/.

## What the game gives you (facts established in pass 1)

- Lua entities: `point` and `brush` types are server-only; `anim` networks and draws;
  `filter` plugs into engine triggers via `ENT:PassesFilter(trigger, ent)`.
- GMod's engine already owns `team_control_point`, `info_player_teamspawn`,
  `path_track`, `func_tracktrain`: a Lua class of the same name never spawns. Their
  keyvalues are recorded by the EntityKeyValue hook in sv_world.lua (`WS.KeyValues(ent)`,
  outputs as an ordered list in `.outputs`), inputs are intercepted with the `AcceptInput`
  hook, outputs fired with `WS.FireOutput(ent, name, activator)`.
- `team_control_point` state lives in sv_controlpoint.lua (owner, lock, model).
- `func_tracktrain` accepts `SetSpeedDirAccel` and `SetSpeedForwardModifier`; its
  `m_flSpeed` is readable with `GetInternalVariable`. path_track `OnPass` can be
  subscribed to with `AddOutput`.
- A brush entity's `OBBMins/OBBMaxs` after `SetModel("*N")` are brush-space; test
  containment with `ent:WorldToLocal(pos)` (works when parented to the moving cart).
- TF2's soundscripts are loaded (sh_soundscripts.lua), so `ply:EmitSound("Announcer.X")`,
  `WS.BroadcastSound(team, "Game.X")` and engine entities' named sounds all resolve.
- Team numbers are TF2's: 0 unassigned, 1 spectator, 2 RED, 3 BLU. `WS.TeamOf(ply)`
  returns 2/3 or 0 for anything else (other addons use other teams, e.g. 21 "Runner").
- Neither Sandbox nor base defines `GM:StartCommand` or server `GM:PostPlayerDeath`;
  do not call BaseClass for those.

## Ownership (edit only your files; request changes to others in your report)

| Agent | Owns |
|---|---|
| **A payload** | entities: team_train_watcher, trigger_capture_area, mapobj_cart_dispenser, dispenser_touch_trigger, NEW tf_logic_multiple_escort; modules: cl_hud.lua, NEW sv_payload*/cl_payload*/foundation/payload*, foundation/capture |
| **B rounds** | entities: tf_gamerules, team_round_timer, team_control_point_master, team_control_point_round, game_round_win, NEW game_forcerespawn, NEW tf_logic_holiday; modules: sv_controlpoint.lua, cl_announcer.lua, NEW sv_rounds*/cl_rounds*/foundation/rounds* |
| **C players** | entities: func_regenerate, func_respawnroom, func_respawnroomvisualizer, func_nobuild, ws_brush_volume, ws_inert_point, ws_pickup_base, ws_trigger_volume, item_*, filter_activator_tfteam, NEW misc (trigger_stun, trigger_add/remove_tf_player_condition, trigger_catapult if GMod lacks it, func_nogrenades, bot_hint_*/func_nav_*/func_tfbot_hint no-ops, entity_spawn_point/manager, tf_ammo_pack); modules: sv_world.lua, sh_core.lua, gamemode/init.lua, NEW sv_teams*/cl_teams*/foundation/teams, foundation/spawn, foundation/players |
| **D spectator** | entities: info_observer_point; modules: NEW sv_spectate*/cl_spectate*/foundation/spectate* (hooks only; no GM overrides) |
| integrator | gamemode/shared.lua, gamemode/cl_init.lua, sh_soundscripts.lua, docs/, .devtools/ |

## Interfaces

Existing, keep signatures stable:

- `WS.TeamOf(ent)`, `WS.EnemyOf(team)`, `WS.Active()`, `WS.State()`, `WS.STATE.*`, `WS.TeamName`, `WS.TeamColor`
- `WS.Rules` (the tf_gamerules entity): `:StateGet()`, `:InSetup()`, `:PointsMayBeCaptured()`,
  `:SetWinningTeam(team, reason, forceMapReset, switchTeams)`, `:OnPlayerDeath(ply)`
- `WS.CapTeam(point)`, `WS.SetPointOwner(point, team, activator)`, `WS.PointLocked(point)`, `WS.PointIndex(point)`, `WS.ApplyPointModel(point)`
- `WS.KeyValues(ent)`, `WS.FireOutput(ent, name, activator)`, `WS.ParseOutput(name, value)`, `WS.FindByName(name)`
- `WS.PlayersInside(ent)`, `WS.IsAliveInGame(ply)`, `WS.HealFraction(ply, f)`, `WS.GiveAmmoFraction(ply, f)`
- `WS.SpawnPoints(team)`, `WS.PickSpawn(team)`, `WS.Announce(text, team)`, `WS.BroadcastSound(team, name)` (team 0 = everyone)
- hooks: `WSRoundActive()`, `WSRoundWin(winner)`, `WSPointCaptured(point, team)`, client `SandcastleHUDPaint(w, h)`

New, each provided by its owner exactly as named (others may call them):

- **B** `WS.TeamCanCapPoint(point, team) -> bool`: not locked, team does not own it, previous points owned, point belongs to the current round (if rounds are in use). A's capture areas call it.
- **B** `WS.CurrentRound() -> team_control_point_round entity or NULL`; hook `WSMiniRoundStart(round)` after a mini-round begins (after its spawn changes apply).
- **B** `WS.SwitchTeams()`: swap every RED/BLU player (used by switch_teams on win). Implement via `WS.SetPlayerTeam`.
- **B** hook `WSOvertime(active)` when the timer enters/leaves overtime.
- **C** `WS.SetPlayerTeam(ply, team)`: the one way to change a player's TF2 team (TF2 semantics: a live player switching teams dies and respawns with the waves; spectator).
- **C** `WS.RoundSpawnFilter` is not an API; C decides spawn selection per round from `WS.CurrentRound()`.
- **D** `WS.StartObserving(ply)` / `WS.StopObserving(ply)`: put a player into / out of observer mode (dead players and the spectator team). C's `WS.SetPlayerTeam` calls them for team 1.
- **D** `WS.SetRequiredObserverTarget(name)` (name, or "" to clear): B's tf_gamerules input SetRequiredObserverTarget calls it.
- **A** each watcher entity: `:TimerMayExpire()`, `:IsWatching(train)`, `:SetNumTrainCappers(num, area)` (existing).

## Networked keys (Global2 vars)

Keys are snake_case with the `ws_` prefix, named for what they hold.

- B owns and may add, not rename: `ws_rounds_active`, `ws_round_state`, `ws_round_in_setup`, `ws_round_winner`, `ws_preround_end_time`, `ws_round_overtime`, `ws_timer_{shown,paused,time_left,end_time,in_setup,auto_countdown,serial}`.
- A owns `ws_cart_*` and `ws_capture_*` and may reshape them for several carts (A also owns cl_hud.lua, which reads them and the timer keys).
- Anything else: prefix with your area after `ws_` (`ws_round_*` B, `ws_team_*` C, `ws_spectate_*` D).

## Conventions

- Behaviour comes from TF2's code: source-sdk-2013 at `~/Repositories/source-sdk-2013/src/game/` (server/, shared/, shared/tf/, server/tf/, client/tf/). Cite the C++ function a behaviour comes from in a short comment where the reason is not obvious. Keyvalues, inputs and outputs of every entity are in TF2's FGD: `$TF2/bin/tf.fgd` (also queryable via the tf2vscript MCP tool `entity_io`), where `$TF2="$HOME/Library/Application Support/CrossOver/Bottles/Team Fortress 2/drive_c/Steam/steamapps/common/Team Fortress 2"`.
- Map data: `.devtools/bin/bsp_entities.py $TF2/tf/maps/<map>.bsp [--json | --class C | --io]` dumps any map's entities; use it to see how real maps use an entity before implementing it.
- TF2's own convar names and defaults (from the SDK) for TF2 settings; `ws_*` for Sandcastle-only settings.
- Code style (from the operator's rules): pure logic goes in `foundation/<system>.lua` or `foundation/<system>/<part>.lua` (a `module(...)` loaded with `WS.require`) with a LuaJIT test written first and seen failing; no defensive fallbacks for states the code rules out; small functions with one job; comments only for constraints the code cannot show. Match the existing files: tabs, `local` helpers, INPUTS tables keyed by lowercased input name, `ENT:KeyValue` storing `On*` via `StoreOutput`.
- Every Lua file must pass `luajit -b <file> /dev/null`; `.devtools/bin/run_lua_tests.sh` must pass.
- Do not use the live game (`.devtools/bin/gmod_lua.py`) and do not launch or close Garry's Mod or Steam: the integrator tests in game after merging.
- Commit in small units on your branch: `git -c gpg.program=gpg-loopback commit -m "..."`. Never add Co-Authored-By or any Claude attribution. Do not push. Messages explain what and why.

## Census: TF2-only entity classes in the 49 installed pl_/plr_ maps

17 classes are in every map (all implemented in pass 1). Then: game_round_win 41,
item_healthkit_full 38, team_control_point_round 36, game_forcerespawn 21,
tf_logic_holiday 13, entity_spawn_point/manager 12, tf_logic_multiple_escort 9 (every plr_),
tf_spell_pickup 8, tf_zombie_spawner 8, trigger_add_tf_player_condition 8, trigger_stun 7,
bot_hint_* / func_nav_* a few, func_nogrenades 4, trigger_catapult 2. Full list: docs/payload-census.txt.
