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
- **CS:S's weapons are built, unchecked in game** (`gameplay.css_weapons`,
  below); the buy menu is not started: players get them from the spawn menu
  (category Counter-Strike: Source), the war's soldiers from the scenario's
  kits.

## CS:S's weapons

All 28 of CS:S's weapons but C4 (the bomb, for defusal): 24 guns, the knife
and the three grenades, under CS:S's own class names (`weapon_ak47`, ...),
shown by GMod's own c_ models (`models/weapons/cstrike/c_*.mdl`, which GMod
ships: they take the player's hands, and need CS:S mounted for their
textures), with CS:S's sounds.

- **From the game's files.** `.devtools/bin/css_weapons.py` reads CS:S's
  weapon scripts out of `cstrike_pak_dir.vpk` (`scripts/weapon_*.ctx`,
  ICE-encrypted: `.devtools/bin/ice.py`) and its English names, and writes
  `games/gameplay/css_weapons/scripts.lua`: price, team, damage, pellets,
  cycle, range and range modifier, clip, ammo, speed, and the accuracy
  model's numbers (spread; standing, crouching, moving, jumping, landing,
  ladder and firing inaccuracy; recovery times; a second set for the second
  mode). Run it again after a CS:S update.
- **The accuracy model** is the scripts', played as CS:S's successor plays
  it: a shot's inaccuracy is the penalty, plus movement past a third of the
  weapon's speed, plus the air or a ladder; each shot adds its fire penalty
  and the excess falls ninefold over the recovery time. Bullets spray from
  one offset in the inaccuracy, each within the spread, aimed along the view
  plus its punch. Damage falls by the range modifier every 500 units, times
  CS:S's hit groups (head 4, stomach 1.25, legs 0.75); the balance leaves it
  whole and a headshot is no TF2 crit on top.
- **Tuning, not from the game** (`css_weapons.lua`, near CS:S as it plays,
  never read from its code, which is not public): recoil (KickBack for the
  automatics, a punch a shot for the rest), burst timings, scope fields of
  view, ammo carried, reload seconds for NPC soldiers, the knife's strikes
  and backstab, the grenades' damage, radius, blindness and smoke.
- **No shot kills from full health but a skill shot** (for every weapon,
  HL2's too: `weapon_balance` `Cap`, applied last in `ws/sv_hits.lua`): a
  player's or soldier's shot, its pellets together, deals a fighter at most
  `HIT_CAP` (80 %) of its most health; what it could not deal pushes and
  staggers instead (`OVERFLOW`, the stronger of that and the weapon's own
  knockback). The skill shots, uncapped: a bolt-action sniper rifle's (AWP,
  Scout) through its scope and the knife's backstab; not the automatic
  snipers, which CS:S's players call skill-free (`Css.SkillShot`, told by `WS.SkillShot`). Before
  it, 22 of the 24 CS:S guns killed with one headshot at 100 health, and the
  M3, XM1014 and AWP with one body shot; of HL2's, the .357's headshot (225),
  the shotgun's close crit (168) and the frag, SLAM and RPG blasts.
- **CS:S out-damages HL2 three to six times** over time: at 500 u an AK
  deals 353 a second to the body, the M249 424, an MP5 273, against the
  AR2's 80 and the SMG's 53 (pistols: Glock 125, Deagle 194, against HL2's
  pistol 60, .357 75). Left as CS:S has it; scaling it to HL2's pace is open.
- **What CS:S's players think of them** (community threads and the
  Counter-Strike wiki, 2026-10-29): competitive play is "AK/M4/Deagle/AWP",
  "most the other guns just can't compete"; the Deagle and the AWP are loved
  for the one-shot skill they reward (the AWP's skill exempt from the cap
  above; the Deagle's headshot capped). The auto snipers are hated as
  skill-free, not as weak. The least loved: the UMP-45 (its achievement the
  least earned of all CS:S's weapon achievements), the TMP (the weakest
  primary, "unpopular"), the Five-seveN (among "the least popular
  pistols"); the P228 split opinion and is next if one more is wanted.
- **The least loved get a twist, not damage, and each twist is a TF2
  player condition** its hit inflicts (`Css.TWISTS`, `weapon_css_base`'s
  `Hit`, `WS.Inflict`; a hit while one is held lasts the longer,
  `gameplay.players` `Inflict`): the UMP-45, `MAD_MILK` (3 s; whoever
  hurts its victim heals 60 % of the damage, TF2's ApplyOnHitAttributes,
  new to Sandcastle); the TMP, `BLEEDING` (2 s; TF2's bleed, 4 every
  0.5 s from the hit on its own clock, `BleedTick`, dealt in the shooter's
  name, now implemented for any source); the
  Five-seveN, `MARKED_FOR_DEATH` (3 s; mini-crits from anyone, new to
  Sandcastle). The victim's own controls are never touched: no twist
  stuns, as a stun belongs to a projectile that takes skill to land and
  hitscan bullets land too often to bear (the UMP-45's 0.4 s slow was
  tried and dropped for it), and an aim flinch was tried and dropped as it
  did not read as the shooter's doing. Teammates
  are spared as their bullets are. Bleeding and the mark are in the C
  menu's condition toggles, and show as TF2 shows them: a bleed is
  `effects/bleed_overlay` on its holder's screen, a mark is `item_fx.pcf`'s
  `mark_for_death` 20 units over the eyes, seen by all but its holder. Mad
  Milk keeps its drips and loses its screen overlay, which TF2 left
  commented out. The NPC
  soldiers' guns (`nextsoldier.weapons`) have no twist; the war's bot
  players do.
- **Second modes**: the M4A1's and USP's silencer (its own animations,
  sound, no tracer, the script's second accuracy, which keeps the gun's one
  pair of recovery times as CS:S does), the Glock's and FAMAS's
  burst, the scopes (AUG and SG 552 one level, the snipers two; a bolt
  action drops its scope until it may fire again; a sniper's scope covers
  the view). Shotguns load a shell at a time.
- **Soldiers**: on the hostage maps RED carries the terrorists' arms (AK-47
  or Galil, Glock, knife) and BLU the counter-terrorists' (M4A1 or FAMAS,
  USP, knife); blockers the M3, raiders a MAC-10 or MP5, support the M249 or
  P90 (`Scenario:Kit`). Medics keep their faction's kit.

Still open:

- **Checked in game (2026-10-29, de_dust2, bots frozen, real shots)**: the
  cap (a 300 hit deals 80, the victim left at 20 and pushed at 327 u/s; an
  unscoped AWP and a scoped G3SG1 deal 80), the skill shots (a scoped AWP
  and Scout kill), the twists (the UMP-45's stun, since replaced by Mad
  Milk; the TMP bleeds 4 at 0.5 s and 1.0 s after the hit, in the shooter's
  name;
  the Five-seveN marks 3 s and a marked victim takes 13 of a 10), each
  networked to clients. The check found every second mode's shot erroring
  (no recovery times in the second accuracy) and bleeds ticking on one
  shared clock; both fixed.
- **Still to check in game**, with a client: the c_ models' framing (`WS.CSS_VIEWMODEL_FOV` 54), the
  scope overlay's arcs (`sprites/scope_arc`, its quadrants' orientation),
  the silencer and Elites' animations, a shotgun's loading, recoil's feel,
  grenades' throws, flash and smoke, and the bots' fire with each kit.
- **No wall penetration** (the scripts' `penetration` is kept, unused), no
  armour (`armorRatio` kept), no movement speed by weapon (`maxSpeed`, a
  scope's `speed`: Sandcastle's movement is TF2's).
- **Smoke and flashes do not blind the bots**, whose vision is their own.
- **The buy menu**: `For(team)` gives a side's weapons and `price` CS:S's
  prices, for the store when it comes; the loadout's catalog is untouched.
- The silenced M4A1 and USP keep their bare world models.

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
