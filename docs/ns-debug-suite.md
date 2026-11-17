# Moving the NPC debug suite into NextSoldier

**Status: plan, approved in outline by the operator (2026-11-17); phases land
one at a time, each committed and pushed.**

## Why

Club Random's citizens are NextSoldier bots now (base_nextsoldier, their lives
as foundation state charts), but the way to see what a bot is doing (the
`ws_nb_*` layers, the overlay, the C-menu's *Select NPC for Debug* and *Debug
NPC*, the *Utilities › Debug NextSoldier* panel) lives in Sandcastle's
wetsands gamemode, the `nbdebug` feature, and runs on Sandcastle's own
infrastructure. A mode that hosts NextSoldier should get it with the bots.

## What is there today

| Piece | Lines | Sandcastle it needs |
|---|---|---|
| `features/nbdebug/model.lua`: layers, filter, selection, subscriptions, cost recorder, path report, behavior log | 897 | `npc.nextbot`'s result numbers |
| `features/nbdebug/sh.lua`: the wire format | 220 | `WS.Events` (the event registry on net2) |
| `features/nbdebug/sv.lua`: the controller | 511 | `WS.Events`, `WS.Feature ("npc"):WatchPaths`, `WSNpcPathComputed`, `WSNpcMark` |
| `features/nbdebug/cl.lua`: the overlay | 608 | `WS.Events`, `WS.HUD`, team colours |
| `features/nbdebug/{ns_overlay,aiwar_overlay,cl_marks,cl_rooms}.lua` | 253 | the AI war's parts |
| `cl_nb_menu.lua` (C-menu), `cl_ns_debug.lua` (panel), `sv_nbdebug.lua` (commands) | 291 | `WS.Can (NPC_DEBUG)`, `WS.SetServerSetting` |

About a third is the AI war's: squads, contacts, lanes, battle lines, rooms.

## The seam

NextSoldier gets the generic suite; each mode adds to it.

- **NextSoldier** (`lua/nextsoldier/debug/`): the model (layers PATH, COST,
  BEHAVIOR, LOOK_AT, NAV, MARKS), the controller, the overlay, the C-menu
  entries and the Utilities panel. Its commands are `ns_debug_*`
  (`ns_debug`, `ns_debug_select`, `ns_debug_filter`, `ns_debug_dump`,
  `ns_debug_behavior_print`), after docs/ns-split.md's names.
- **Transport**: plain GMod `net`, one message per event (`ns_debug_state`,
  `ns_debug_path`, ...), fields written in a fixed order. It is admin-only and
  low volume, so NextSoldier does not take Sandcastle's net2 and event
  registry with it. The model's byte budget (`MAX_COST_AREAS`) still bounds
  the largest message.
- **Feeds**, which any bot or mode raises: a path computed
  (`NSDebugPathComputed (ent, report)`, base_nextsoldier's watched search
  already records one), a mark (`NSDebugMark (ent, kind, detail, from, to)`),
  the behavior stack (base_nextsoldier's `NSDebugStack` and `NSDebugWatch`,
  which a class with its own life overrides).
- **Permission**: the host port gains `MayDebug (ply)`, shared. Sandcastle
  answers with `WS.Can (ply, NPC_DEBUG)`; Club Random with superadmin or the
  `Developer` usergroup.
- **Extension**: a mode adds a layer of its own (Sandcastle's AIWAR) through
  hooks the overlay raises: lines in a bot's box (`NSDebugBoxLines`), world
  drawing (`NSDebugDrawWorld`), entries in the C-menu
  (`NSDebugMenu (menu, ent)`), and sections in the panel
  (`NSDebugPanel (panel)`).

## Phases

1. **Model into NextSoldier.** `nextsoldier/debug/model.lua` from
   `features/nbdebug/model.lua` without AIWAR, its result names read from
   `generator.state_chart`. Its tests move with it
   (`features_nbdebug_model_test` becomes `ns_debug_model_test`).
2. **Controller, wire, overlay, menus into NextSoldier**, with `MayDebug` on the
   host port and the `ns_debug_*` commands. Tests: the wire's round trip,
   the panel's and contract tests moved over.
3. **Club Random hosts it**: `MayDebug` (superadmin or Developer), its
   citizens' stacks through `NSDebugStack`; its own `sv_citizens_debug`
   overlay goes. Checked live on gm_mobenix_v3_final.
4. **Sandcastle on NextSoldier's suite**: its `nbdebug` keeps the AIWAR layer,
   rooms and the AI war's marks as extensions; `ws_nb_*` stay one release as
   aliases printing their new names. Sandcastle's tests stay green.

Each phase ships alone and keeps every repo's tests green.
