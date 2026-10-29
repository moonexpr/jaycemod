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

## Built

CS:S's sides are RED (terrorists, who keep the hostages) and BLU
(counter-terrorists, who lead them to their spawn); no new team ids.

| Piece | Where | Tests |
|---|---|---|
| The rules as an immutable round | `features/hostage/model.lua` | `features_hostage_model_test` |
| Hostage groups, and squads bound to them | `features/hostage/groups.lua` | `features_hostage_groups_test` |
| The rescue zone round BLU's spawns | `features/hostage/zone.lua` | `features_hostage_zone_test` |
| The rounds mode (arena-like, untimed, no respawns) and `HOSTAGES_RESCUED` | `features/hostage/round.lua`, `games/gameplay/rounds.lua` | `features_hostage_round_test`, `features_rounds_text_test` |
| The AI war's scenario: BLU rescuers, RED's new HostageDefender | `features/aiwar/scenario/hostage.lua` | `aiwar_hostage_test` |
| The controller and `hostage_entity` | `features/hostage/sv.lua`, `entities/entities/hostage_entity.lua` | live only |
| CS:S spawns for RED and BLU | `features/aiwar/spawns.lua`, `sv_map.lua` | `aiwar_cs_spawns_test` |
| An instance running a worktree's gamemode | `.devtools/bin/server_root.py` (`SANDCASTLE_GAMEMODE`) | `test_server_root.py` |
| Watching a match | `.devtools/bin/hostage_watch.py`, `hostage_status.lua` | |

Squads: each team forms a squad for every hostage group (`war:SetSquadsMin`,
raised to the group count, never lowered) and every squad owns one group.
BLU: free the nearest held hostage of the group, the soldier with one
following leads it (going back when it lags `LEAD_LAG`), the squad escorts, a
settled squad helps the other group, then hunts RED. RED: guard the group's
hostages tight (`HOSTAGE_RING`, `HOSTAGE_LEASH`) where they stand now, recover
a taken one at once past the leash, cover another group once its own is
settled, and once the hostages have been quiet `HUNT_AFTER` seconds hunt the
nearest BLU soldier (the first of each squad after `HUNT_ALL_AFTER`), so a
round cannot stall with BLU alive. BLU takes 60% of the soldiers.

## Seen live (cs_office, instance 2, 2026-10-28)

- RED won many rounds by killing all of BLU ("opponents dead"), and a game
  ended on it (the server then rotated to the next map).
- BLU freed hostages of both groups and led them into the zone (`rescued`),
  and won one round (RED eliminated, three rescued, the fourth following).
- Not seen: the `HOSTAGES_RESCUED` win itself, all four led out. A run with
  everyone invulnerable (so only the rescue could end it) stalled: the leader
  and two hostages stood still near (1250, 170) and most of BLU sat at its
  spawn. Not diagnosed; invulnerability may itself be the cause.

## Fixed since (2026-10-29)

- **Gamerules:** `cs_gamerules` (on `ws_gamerules`) runs the hostage mode
  (`Mode.RULES_CLASS`) and answers CS:S's round-end inputs
  (`features.hostage.rules`).
- **Round timer:** `mp_hostage_roundtime` (240 s); when it runs out RED wins
  (`HOSTAGES_NOT_RESCUED`, via `Mode:StalemateTimerWin`).
- **Match length:** `mp_winlimit 0`, `mp_maxrounds 10` (`WIN_CONDITIONS.HOSTAGE`);
  the default win limit of 2 had ended matches after two round wins.
- **Spawns:** each team at its own side (`gameplay.spawn` `SIDE_CLASSES`); GMod's
  base picker had spawned players and bots on either side at random. Checked
  live: 64 spawns, none on the wrong side.
- **Rescue zones:** the map's own `func_hostage_rescue` brushes, the one nearest
  BLU's spawns first.
- **Hotfixes** (`features.hostage.hotfixes`, applied at load, mesh files
  untouched): `cs_office`'s link through the wall at the T exit, and its eleven
  dumpster lids, named one by one.
- **Team sizes:** new bots join the team furthest below the scenario's size, so
  BLU really is 10 to RED's 6 at `mp_aiwar_team_size 8`.
- **The stall** was soldiers stuck on corners: bot soldiers are TF2 players 48
  wide, but every walk check swept 26. Fixed for all modes (`BotSoldier:Sweep`,
  the lanes, the nav seam links); on `cp_sunshine` 2 recoveries in 6 minutes
  after, none disabled. The route mesh also failed to build on maps with a nav
  area's top attribute flag set (signed read); fixed.

## Open

- **The other cs_ maps** (`cs_assault`, `cs_compound`, `cs_havana`, `cs_italy`,
  `cs_militia`) have no nav mesh yet, so no hotfixes are known for them.
- **Hazards on the server roots** were laid during the 26-wide-sweep bug; the
  hazards module forced match closures on `cs_office` until cleared
  (`ns_hazards_clear all`). Other maps' files on both roots likely hold false
  hazards from the same bug.
- **The Female Civilian model has two sequences** (a reference pose): it
  cannot animate, so a following hostage of that model slides in a T-pose.
- The hostage NPC is a plain nextbot with a path follower and a hop when stuck;
  it cannot be hurt.
- Human players using a hostage (the controller takes any BLU player within
  `USE_RANGE`) is untested.
- Loadouts and the buy menu are not started.

## The hostages' models

Two Workshop addons, downloaded by steamcmd (`SERVER_DOWNLOADS` in
`.devtools/bin/server_root.py`, so the server needs no operator subscription)
and mounted from `cache/`:

| Name | Item | Models |
|---|---|---|
| `hostage_civilian` | 3172805326, TF2 Classified Civilian/VIP | `models/player/team/fortress/npc_arces_{red,blue,green,yellow}_civilian.mdl` (the archive also has player and `jerknpc_` hostile variants, and c_arms) |
| `hostage_fem_civilian` | 886058416, Maxxy's TF2 Female Civilian | `models/player/hwm/fem_civilian.mdl`, `fem_civilian_flexible.mdl` (skirt bones move; GMod's) |

`features/hostage/models.lua` lists them (`MALE`, `FEMALE`, `All`, `Pick`);
`features/hostage/resources.lua` has the feature preload them. Fetch with
`steamcmd +login anonymous +workshop_download_item 4000 <item> +quit`.
The Female Civilian's loose-files zip from the author's page has the same
model paths; the Workshop download is what the server uses.

Checked live: the Classified Civilian NPC models have a full animation set
(`run_all`, `idle_subtle`); the Female Civilian has two sequences and cannot
animate (see Open).
