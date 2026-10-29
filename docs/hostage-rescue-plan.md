# Hostage rescue (CS:S, cs_office)

The first CS:S mode, on `cs_office`: Counter-Terrorists lead hostages to a
rescue zone; Terrorists stop them. Sandcastle's TF2 modes are the pattern: a
feature folder with a pure model, a controller that binds map entities, and
tests first.

## Rules (Valve Developer Community, "Hostage Rescue")

- A hostage is held where the map put it, follows whoever uses it, and ends
  rescued (led into a rescue zone) or killed.
- The Counter-Terrorists win when no hostage is unresolved (held or
  following) and at least half of all were rescued.
- With fewer rescued, the round runs on; the Terrorists win by time or by
  killing the Counter-Terrorists. No draws.
- Source's bug (rescuing the last hostage wins however many died) is not kept.

## Done

`features/hostage/model.lua`, tested by `tests/features_hostage_model_test.lua`:
the rules above as an immutable round (`Follow`, `Release`, `ReleaseFrom`,
`Rescue`, `Kill`, `Outcome`). It knows nothing of entities, teams or zones.

## Not done, in the order they depend on each other

1. **Teams.** `gameplay.teams` holds TF2's RED and BLU. CS:S needs T and CT
   (`docs/foundation-simplification-plan.md` defers this to the first CS:S
   consumer). Decide: new team ids, or CS:S sides mapped onto RED/BLU.
2. **The round mode.** A `rounds` mode (like `features/arena/round.lua`) with
   no respawns, a round timer, and win reasons for the two sides.
3. **Map entities**, as Lua bindings in `gamemode/entities/entities/`:
   `hostage_entity` (an NPC variant on `ws_nextbot` whose behaviour follows its
   rescuer; `docs/pass3-halloween.md` section 12), `func_hostage_rescue`
   (the zone), `info_player_terrorist` and `info_player_counterterrorist`
   (spawns), `func_buyzone` (no buying yet).
4. **The controller**, `features/hostage/sv.lua`: loaded by a `hostage_entity`,
   builds the round from the map's hostages, turns use, zone entry, death and
   disconnect into model moves, and ends the round on `Outcome()`.
5. **The map.** `cs_office` is not in this repository. It needs mounting on
   the dev server, a nav mesh (CS:S meshes need verifying against
   `nav_convert.py`), and a `dev_cs_office_*` test map per the naming rule.
6. **Loadouts.** CS:S weapons and the buy menu; out of scope until 1 to 4 run.
