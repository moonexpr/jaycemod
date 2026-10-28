# Splitting NextSoldier out of the AI war

**Status: plan, for the operator's approval. Nothing below is built.**

## 0. The distinction

The operator's distinction (2026-10-27), which replaces this plan's first
one (NextSoldier as the soldier AI with its tactical planning):

- **NextSoldier (NS)** is the agent itself, built on NextBot: how a soldier
  moves (travel, doors, leaps, rappels), what it senses (sight, hearing),
  its body, voice and behaviours. It is a library, and it runs on its own,
  without the tactics engine. It knows nothing of rounds, carts, points or
  who won. `gamemode/nextsoldier/`.
- **The war tactics engine** (`wartactics`) is the high-level strategy the
  soldiers are organised by: a fire team's doctrine, squads, lanes, posts
  and battle lines, the setup zone, the hunt, the scenarios, the bot quota.
  It stands on NextSoldier, never under it
  (`tests/foundation_layers_test.lua` ranks it above). `gamemode/wartactics/`.
- **AIWar** is a multiplayer system. It adds PvE that plays like PvP: bot
  sides fighting the map's own round. It decides who fights, for which side,
  in which job, and when the dead come back. It uses NS for the soldiers.

Today both live in `foundation/aiwar/` and `features/aiwar/`. Only this
session's debugging tools are named NS (`foundation/ns/`, `ns_*` commands
and convars, `docs/ns-debugging.md`). The goal is one direction of dependency:
**AIWar → NS → foundation.npc**, with nothing in NS requiring
`foundation.aiwar*`.

## 1. The seam

NS offers a mode four things, and a mode gives NS three:

| NS offers | AIWar gives |
|---|---|
| the soldier tree (`NextSoldier` … `Travel`) and the soldier port | **jobs**: a doctrine of job strategies (`Goal`, `Zone`, `Urgent`, `Line`, `arrive`, `leash`, `rushes`), as `orders`' `ROLES` are today |
| squads (fire teams, leaders, claims) and their tactics (contact, bound, flank, fall back) | **allocation**: each soldier's job and side, pulled by `StrategyMonitor` |
| lanes, posts and battle lines, planned over the nav mesh | **the field**: fronts, objectives and threats as positions, never carts or points |
| the debugging tools (overlay, reports, tuning) | **round events**: won or lost, so the tactical monitor can humiliate or hunt |

The rule that makes the seam: NS reads positions and job strategies. Every
rule about carts, checkpoints, capture points or clocks lives on the AIWar
side of a doctrine.

## 2. Module map

| Today | Goes to | Why |
|---|---|---|
| `aiwar/orders.lua`: the tree, monitors, `Travel`, `Chase`, `RetreatToCover`, squad roles, `Objective`'s fight (`Fight`, `Attack`, `Defend`, `Regroup`, `FollowLeader`, `Roam`, cover claims) | `ns/orders.lua` | soldier behavior |
| `aiwar/orders.lua`: `ROLES` (Push, Escort, Block, Defend, Raid, Support, Medic), `PAYLOAD`, `Focus`, `EnemyLine`, cart helpers | `aiwar/doctrine/payload.lua` | payload's jobs read carts |
| `aiwar/scenario/control_points.lua`'s point doctrine | `aiwar/doctrine/points.lua` | the same, for points |
| `aiwar/soldier.lua` (the port) | `ns/soldier.lua` | |
| `aiwar/squad.lua`, `tactics.lua`, `lanes.lua`, `posts.lua`, `zone.lua` | `ns/` | tactics and planning |
| `aiwar/overlay.lua` (box layout) | `ns/overlay.lua` (joining the parts) | |
| `aiwar/hunt.lua` | stays in AIWar; NS gets `Humiliated` and `SeekAndDestroy` as actions a mode may run | who hunts whom is the mode's call |
| `aiwar/track.lua` | stays in AIWar | payload track geometry |
| `aiwar.lua`: fire teams, `JoinFireTeam`, `FireTeamMembers`, claims | `ns/roster.lua` | squads are NS |
| `aiwar.lua`: factions, roles, stances, defense share, waves, phases | stays | the mode |
| `aiwar/scenario*.lua` | stays | the mode |

## 3. The controller split

`features/aiwar/sv.lua` (about 2,600 lines) becomes two features:

- **`features/ns/sv.lua`**: the soldier port (`Soldier`), gadgets, relating
  soldiers, the observer and door watchdog, posts, lane planning, the
  overlay snapshot, and the reports and commands. It owns an NS roster
  and runs the soldiers' `Update`.
- **`features/aiwar/sv.lua`**: start and end, enlisting and spawning,
  reinforcement waves, the round, the field (carts, points, clocks,
  gates, setup zone, spawn doors, forcefields), humiliation, and the
  scenario. It asks the NS feature to take a soldier, gives it a job,
  and hands it the field.

`ws/sh_war_soldier.lua`'s bridge talks to NS, not the war.

## 4. Names

Commands and convars the user types are `ns_<subject>_<verb or specifier>`
(`ns_lanes_print`, `ns_lanes_debug`); internal names (hooks, net messages,
networked keys) keep the addon's `ws_` prefix.


| Today | Becomes |
|---|---|
| `ws_aiwar_debug` (toggles the overlay) | `ns_overlay_toggle` |
| `ws_aiwar_report` | `ns_soldiers_print` |
| `ws_aiwar_trace` | `ns_soldier_trace` |
| `ws_aiwar_debug_full` | `ns_stack_debug` |
| the nbdebug layer `AIWAR`, event `aiwar_debug` | layer `NS`, event `ns_debug` |
| `WSNbDebugState` | unchanged (nbdebug's) |
| `mp_aiwar_start`, `_end`, `_team_size`, the AI War panel | unchanged (the mode) |
| `docs/aiwar-command.md` §1, §3 to §6 | `docs/ns-*.md`; §2, §11 stay |

Old command names stay as aliases for one release, printing their new name.

## 5. Phases

Each phase ships alone and keeps `check_lua.sh` and `check_names.py` green,
with the test total never dropping.

1. **Pure moves.** Move the modules that require nothing of the war (`squad`,
   `tactics`, `lanes`, `posts`, `zone`, `soldier`, `overlay`) to `ns/`.
   Rename requires, tests (`aiwar_squad_test` → `ns_squad_test`...) and
   docs. No behavior change.
2. **Doctrines out of orders.** Move `ROLES`, `PAYLOAD` and the cart
   helpers to `aiwar/doctrine/payload.lua`, and the point doctrine to
   `aiwar/doctrine/points.lua`. `orders` then reads jobs only through
   `field.doctrine`. Tests: the orders tests run on a stub doctrine with no
   carts.
3. **Roster.** Fire teams, places, leaders and claims move from `War` into
   `ns/roster.lua`. `War` keeps a roster and delegates. Tests: the squad
   and orders tests build a roster without a `War`.
4. **Orders to NS.** `orders.lua` moves to `ns/`, requiring no
   `foundation.aiwar*` (a test greps its requires). `Hunt` is passed in as
   the mode's, through the field.
5. **The controller split** (§3), then **names** (§4) with aliases.

Phases 1 and 2 pay off alone. Phase 5 is the risky one, since it can only be
checked in game.

## 6. Open questions for the operator

1. **Engine NPCs.** HL2 engine NPCs (`npc_combine_s`...) fight in the war
   today, driven by `foundation.npc` variants too. Are they NS soldiers, or
   does NS mean the DrGBase NextBot soldiers only?
2. **Medics and gadgets.** Healing and gadgets (turrets, manhacks) are
   soldier kit. They go to NS in this plan. Say if they belong to the mode.
3. **Aliases.** Keep the old `ws_aiwar_*` debug commands as aliases for
   a release, or rename outright?
