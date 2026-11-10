# Roadmap

The work ahead, in the order it comes. Each item's design is in the plan it
names under `docs/`.

## Next: to the alpha playtest

1. **net2** (`docs/net2.md`, superseding game events v2). The last system
   before the playtest: local dispatch, self-describing encoding, replicated
   tables, calls, admission and rate limits, in the Sandcastle base gamemode.
   - [x] net2 the transport and game_events on it, with their tests; the round's end announced through them.
   - [ ] Check it in game: the unreliable cap, the per-tick budget, prediction, the world and `NULL` entities.
   - [ ] Move Wetsands' `WS.Events` onto game_events and retire v1's `includes/system/events.lua`.
   - [ ] Cancelling a transfer, a declared schema per name for hot messages.
   - [ ] Move presentation (the announcer, the HUD's reactions) to client listeners.
2. **Multi-file controllers, checked in game**
   (`docs/multi-file-controllers-plan.md`).
   - [ ] The client check after a `changelevel`, and the AI war's lazy loading.
   - [ ] The in-game checks (`ingame_tests.py`).
   - [ ] The client shipping test, which fails on `main`.
   - [ ] Split the long client parts.
3. **The art and UX pass**: one design language, written down
   (`docs/design-language.md`) and applied, and the player journeys walked
   end to end.
   - [ ] Check the Q menu in game.
   - [ ] Write the design language, then audit the menus, HUD, scoreboard, kill feed and voting against it.
   - [ ] Walk the tinkering journey on the dev server, and design the game builder's control-point part and custom weapons.

## The AI war

4. **Bot players** (`docs/aiwar-bots.md`). Bots already fight as NextSoldier
   soldiers under TF2's `tf_bot_quota`; what's left is matching the
   DrGBase soldiers they replace.
   - [ ] Spread route planning over ticks, and cut the per-tick drive cost.
   - [ ] Voice lines, riding and following the cart, battle stances, kits.
5. **Per-tick cost** (`docs/ns-performance-baseline.md`).
   - [ ] LuaJIT's trace capacity under live load.
   - [ ] The respawn hitch, the route-search queue's bursts, the bots' planning hitch.
   - [ ] The think-rate dose runs the baseline's design still calls for.
6. **NextSoldier engineers** (`docs/engineers-plan.md`): sentries,
   dispensers and teleporters built and kept as TF2's engineers do.
   - [ ] The nav sidecar keeping TF2's area attributes.
   - [ ] Map hints read, then the buildings, the engineer model, its mission, teleporter use.

## NextSoldier as a library

7. **Split NextSoldier from the AI war** (`docs/ns-split.md`), so another
   mode can host its soldiers.
   - [ ] A soldier that runs without the tactics engine.
   - [ ] Awareness, detection and relationships as native data.
   - [ ] The entity think measured and moved native where it pays.
   - [ ] Decide whether HL2's engine NPCs are NextSoldier soldiers.
8. **foundation formalism** (`docs/foundation-core-survey.md`): the
   gamemode's hand-written structures moved onto foundation's modules, so
   they run natively on servers. The survey's listed items are done.

## Later

9. **Engine detours** (`docs/native-foundation-plan.md`, "Detouring the
   engine's functions"), blocked on the server binary's symbols.
   - [ ] An engine-side profile that names a hot function.
   - [ ] Read the engine's nav area state (blocked areas, doors) natively.
   - [ ] Nav state that follows moving props in real time.
10. **Nav generation**: a pass for narrow walkable geometry, as its own
    addon, and a reader for TF2's sub-version 2 nav files. Not started on
    purpose.
