# Wetsands on Sandcastle's SDK ports: plan

Status: proposed, for the operator's approval. Nothing below is built but the
interim stand-apart.

## Where things stand

Sandcastle (`gamemodes/sandcastle/`) is gaining ports of TF2's map entities
from source-sdk-2013, written as the SDK writes them:
`team_control_point_master` (158 lines), `team_round_timer` (355),
`trigger_capture_area` (395), with `tf_gamerules` on `sc_gamerules`. Its round
is `round_manager` (197 lines) and `sc_gamerules`, which answers
`TeamplayRoundBasedRules ()` for every TF2 entity, and its games
(`gamerules/game_*.lua`, through `game_manager`) patch each map with the
`logic_sc_*` proxies that join the entities to the round
(`sc_gamerules:Wire` → `game_manager.RunActive ("PatchMap")`).

Wetsands (`gamemodes/wetsands/`, deriving from Sandcastle) still runs a round
of its own, and its own thin bindings of the same entities, which take the
place of Sandcastle's under Wetsands (a derived gamemode's entity shadows its
base's of the same class):

| Binding (Wetsands) | Lines | Feeds |
|---|---|---|
| `team_control_point_master` | 31 | the capture feature (`BindMaster`, `MasterInput`) |
| `trigger_capture_area` | 52 | the capture feature (`BindArea`, `AreaThink`, ...) |
| `team_control_point_round` | | the capture feature (`BindRound`, `RoundPoints`) |
| `team_round_timer` | 71 | the rounds feature (`BindTimer`, `TimerInput`) |
| `tf_gamerules`, `ws_gamerules` | | the rounds feature (`WS.Rules`) |

The two systems do not meet. Wetsands' rounds feature (`features/rounds/`,
3,060 lines) never touches `round_manager`; it holds its round in
`games.gameplay.rounds` and runs TF2's whole round flow itself. Its capture
feature (`features/capture/`, 2,024 lines) holds the points in
`games.gameplay.capture` (1,394 lines).

The round proxy errors were the seam showing: Sandcastle's proxies attached
under Wetsands too (`sc_gamerules` is made on every map; Wetsands' own master
and area bindings `game_manager.Enable ("game_control_points")`), and asked
Wetsands' bindings what only the SDK ports answer: `IsActive`,
`GetTimerPaused`, and nine more.

### The interim stand-apart (built)

`wetsands/gamemode/gamerules/game_teamplay.lua` and `game_control_points.lua`
replace Sandcastle's games of those names (`game_manager`'s rule for a
derived gamemode) with the same rules and standing, but a `PatchMap` that adds
nothing: no `logic_sc_control_point`, `logic_sc_timer_proxy`,
`logic_sc_teamspawn`, `logic_sc_roundrules`, `logic_sc_teamrules`,
`logic_sc_respawn`. `sc_gamerules` stays, answering the Sandcastle-only
entities that run under Wetsands (`game_round_win`, `item_teamflag`,
`team_train_watcher`, `func_regenerate`, `func_respawnroomvisualizer`,
`filter_activator_tfteam`). `tests/rounds_wetsands_games_test.lua` holds it.

Each class copies Sandcastle's own fields onto the same base rather than
reading through Sandcastle's table: `baseclass.Set` merges a class set again
under a name into the first table and gives that table the new one's
metatable, so a class reading through Sandcastle's would read through itself
("loop in gettable" in `game_manager.Active`).

## The goal

Wetsands plays on Sandcastle's round and Sandcastle's ports: its bindings go,
the SDK entities hold their own state, and Wetsands' features read them as
any TF2 code reads its gamerules and entities (`TeamplayRoundBasedRules ()`,
the master's `GetControlPoints`, a timer's `GetTimeRemaining`), reaching the
round through `round_manager` and the games through `game_manager`
(CLAUDE.md: map entities "reach the games through game_manager ... and
round_manager"). The interim gamerules files are deleted at the end.

## Why the order is the round first

The SDK `team_round_timer` thinks off `TeamplayRoundBasedRules ()`
(`SetupThink (rules)`, `RoundThink (rules)`: `IsInPreMatch`,
`RoundHasBeenWon`, `TimerMayExpire`, `SetOvertime`), which is `sc_gamerules`
answering from `round_manager`. A timer moved alone would run against a round
Wetsands does not play. The timer, the gamerules proxy and the master all
move with the round flow, and capture after it.

## What Sandcastle's round lacks

Wetsands' rounds feature's effects (`features/rounds/sv_effects.lua`), each a
thing the round flow does today. Each must be in Sandcastle's round (a
`round_manager` state, an `sc_gamerules` output, a `logic_sc_*` system), or in
a Wetsands feature listening to Sandcastle's round, before Wetsands' flow is
switched off. To audit in slice 1, against `round_manager` and `sc_gamerules`:

| Effect | Notes |
|---|---|
| `balance_teams`, `switch_teams`, `scramble_due`, `scramble_teams` | Sandcastle has `logic_sc_teamrules` (`RequestScramble`) |
| `respawn_all`, `respawn_team`, `freeze`, `unfreeze`, `bonus_freeze` | |
| `arena_round_start`, `arena_setup`, `arena_setup_end` | arena mode |
| `sudden_death`, `sudden_death_over`, `deathmatch` | `game_manager`'s `bonus_suddendeath` |
| `overtime`, `skip_setup`, `stalemate_timer`, `stalemate_winner` | `sc_gamerules:SetOvertime`, `SetStalemate` |
| `time_limit_timer`, `remove_time_limit_timer`, `intermission`, `changelevel`, `next_map` | the map rotation |
| `hide_timers`, `restore_timers`, `activate_timers` | the HUD timer (`PublishHudTimer`) |
| `win_song`, `publish_win`, `score`, `reset_scores` | presentation and scores |
| `doors_lock`, `doors_unlock`, `cleanup`, `clear_gore` | |
| `round_spawn`, `round_activate`, `new_round_outputs`, `previous_round_end` | `sc_gamerules:SetupOnRoundStart` |

## Who reads what moves

The rounds feature, its timer and `WS.Rules` (12 files besides it):
`init.lua`, `features/mvm/sv.lua`, `features/gamemode/sv.lua`,
`features/editors/sv.lua`, `features/graveyard/sv.lua`,
`features/aiwar/sv_field.lua`, `features/aiwar/sv_enlist.lua`,
`features/koth/sv.lua`, `features/builder/sv.lua`,
`entities/ws_gamerules.lua`, `entities/edit_scenario/init.lua`,
`entities/team_round_timer.lua`.

The capture feature and model (20 files besides them):
`sv_teams_spawn.lua`, `sh_editors_point.lua`, `features/payload/{cl,sv}.lua`,
`features/aiwar/sv_field.lua`, `features/aiwar/sv_room_hints.lua`,
`features/koth/sv.lua`, `features/defuse/sv.lua`,
`features/boss_timer/sv.lua`, `features/builder/sv.lua`,
`player_class/player_spectator.lua`, `entities/ent_gameplay_point/init.lua`,
`entities/headless_hatman.lua`, the bindings, `includes/gameplay/sh_init.lua`.

Clients: the HUD reads the rounds feature's published timer and the capture
feature's points (`features/rounds/cl.lua`, `cl_objectives.lua`); the SDK
ports network their own state (`team_round_timer`'s NetworkVars), which the
HUD would read instead.

## Slices

Each slice: LuaJIT tests first (`check_lua.sh` for its groups), then on the
dev server a scenario saved before it (`scenario_save`) played through on
pl_upward (payload), koth_viaduct (KOTH) and cp_dustbowl (A/D control
points, mini-rounds), with no Lua errors and the round's events
(`game_events`) as before. Commit and push as each passes.

1. **Audit.** Each effect above against Sandcastle's round: present, missing,
   or Wetsands' alone (a feature that listens to Sandcastle's round). A table
   added here; the operator decides which of the missing go into Sandcastle.
2. **Sandcastle's round gains what it lacks**, in Sandcastle, played on the
   Sandcastle gamemode first (Sandcastle must stand alone).
3. **Wetsands' round on `round_manager`.** Wetsands' rounds feature becomes a
   listener of Sandcastle's round (its presentation, its own effects), its
   state machine off. `WS.State` and `WS.Rules` answer from
   `TeamplayRoundBasedRules ()`, then their readers move to it and they go.
   Wetsands' `game_teamplay` interim file goes; `logic_sc_roundrules`,
   `logic_sc_teamrules`, `logic_sc_respawn` and `logic_sc_teamspawn` run under
   Wetsands. `sv_teams_spawn.lua`'s input hook goes for `logic_sc_teamspawn`.
4. **The timer.** Wetsands' `team_round_timer` binding goes; the rounds
   feature's timer model and `BindTimer`/`TimerOf`/`PublishHudTimer` go; the
   HUD reads the SDK timer's NetworkVars.
5. **The gamerules.** Wetsands' `tf_gamerules` and `ws_gamerules` go;
   `tf_gamerules` is Sandcastle's, on `sc_gamerules`.
6. **Capture.** Wetsands' master, area and round bindings go; the capture
   model's readers (the table above) read the SDK entities; the capture
   feature keeps what is Wetsands' own (the editors' points, the AI war's
   field) or goes. Wetsands' `game_control_points` interim file goes, and
   with it the stand-apart.

## Risks

- Behaviour the rounds feature has that Sandcastle's lacks, lost in slice 3:
  the audit (slice 1) is there to make each loss a decision.
- The AI war reads the round and the points throughout (`sv_field.lua`,
  `sv_enlist.lua`, wartactics' scenarios); its scenarios on each map are part
  of each slice's check.
- The dev server's `server.cfg` forces gameplay and the AI war each map
  (memory: dev-server-cfg), so a slice's check runs under it.
