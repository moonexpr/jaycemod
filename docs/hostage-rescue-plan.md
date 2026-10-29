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

## Open

- **Nav area 757**, a 25-wide strip at (1212, 375) on the route into group 1,
  with two links through world geometry, stranded soldiers again and again.
  The client's mesh needs fixing there, or the hazards module to cope.
- **The Female Civilian model has two sequences** (a reference pose): it
  cannot animate, so a following hostage of that model slides in a T-pose.
  The Classified Civilian NPC models (1417 sequences) animate.
- BLU is outgunned: RED wins most rounds. The 60% share (`TeamSizes`) did not
  show up with `tf_bot_quota 0` (teams were 8 and 8): the bot actor's team
  sizes are not the scenario's yet.
- The hostage NPC is a plain nextbot with a path follower and a hop when stuck,
  not a `ws_nextbot` variant; it cannot be hurt.
- The timeout is untimed by design; a stalled round is ended only by the hunt.
- Human players: spawns and a way to use a hostage (the controller takes any
  BLU soldier or player within `USE_RANGE`) are untested.
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
