# Sandcastle pass 4: King of the Hill and Control Point maps

Pass 4 makes the 44 installed koth_ maps and 57 cp_ maps play their rounds
as in TF2, and turns the always-loaded round and control point code into
lazily-loaded features with foundation models behind them. Payload keeps
working at every merge. Everything in `docs/pass2-contract.md` and
`docs/pass3-halloween.md` still holds (layout, conventions, commits, the
Model / Controller / Entity / View layers, `WETSAND.Feature`).

`sdk/` means `~/Repositories/source-sdk-2013/src/game/`. `$TF2` is
`$HOME/Library/Application Support/CrossOver/Bottles/Team Fortress 2/drive_c/Steam/steamapps/common/Team Fortress 2`.
Map facts come from `.devtools/bin/bsp_entities.py "$TF2/tf/maps/<map>.bsp" [--class C | --io]`
and the new `.devtools/bin/map_census.py koth_ cp_` (section 1.3).

Baseline on 757cd62: `check_names.py` ok (272 files), `check_lua.sh`
compiles 272 files, 848 tests pass, 0 fail.

## 0. Decisions the operator should know

1. **Fourteen of the maps have no `tf_gamerules`**, among them cp_dustbowl,
   cp_gorge, cp_gravelpit and koth_sawmill. Today they play as plain Sandbox.
   TF2 always creates a gamerules proxy named `tf_gamerules`
   (`CTFGameRules::CreateStandardEntities`, `sdk/shared/tf/tf_gamerules.cpp`).
   The rounds controller does the same: when an objective entity has loaded
   it and the map has no `tf_gamerules`, it creates one named `tf_gamerules`.
   Outputs aimed at `tf_gamerules` then reach it through the engine's
   classname fallback (`CEventQueue::ServiceEvents`, `sdk/server/cbase.cpp`).
2. **The round and win rules become a model, and the modes become its
   strategies.** `foundation.rounds` turns from a function library into a
   stateful `Round` model: TF2's gamerules state machine, wins, sudden death,
   limits, respawn waves, setup, overtime and `TimerMayExpire`. Three modes
   plug into it: `foundation.rounds.control_points`, `.koth` and `.payload`.
   Map entities choose the mode: `tf_logic_koth` gives KOTH,
   `team_train_watcher` gives payload, and `team_control_point_master` gives
   control points. When several are present, the highest `PRIORITY` wins, as
   in `CTFGameRules::Activate`. Nothing checks the map name.
3. **Symmetric CP and attack/defend are one strategy, not two.** TF2 has a
   single CP rule set (`TF_GAMETYPE_CP`). A/D is data: a master's
   `cpm_restrict_team_cap_win`, rounds, setup timers, and a `game_round_win`
   wired to `OnFinished`. The strategies split where TF2's code splits: CP,
   KOTH (`IsInKothMode` branches) and escort. The HUD can still tell the two
   CP flavours apart from the data.
4. **`tf_gamerules` becomes a thin binding.** Its 842 lines of rules move
   into the `Round` model and the `rounds` controller. The entity keeps its
   public methods as one-line forwards (`OnPlayerDeath`, `Halt`,
   `RestartRound`, `SetWinningTeam`, ...), so `init.lua`, aiwar, editors and
   gameplay need no changes.
5. **Loading is per map.**
   - A KOTH map loads `rounds`, `capture` and `koth`.
   - A CP map loads `rounds` and `capture`.
   - A payload map loads `rounds`, `capture` and `payload`.
   - A non-TF2 map loads none of these.

   Six realm files are deleted: `sv_rounds.lua`, `sv_controlpoint.lua`,
   `sv_payload.lua`, `cl_rounds.lua`, `cl_announcer.lua` and
   `cl_payload.lua`. `cl_hud.lua` is split up and then deleted.
6. **Six gaps that break real maps today:**
   - `TimerMayExpire` ignores captures in progress, so A/D defenders win
     while attackers stand on the point, and CP and KOTH never go into
     overtime.
   - `logic_auto`'s `OnMultiNewRound` never fires. 56 of the 101 maps use it
     (359 connections) for goal strings, wave times, roles, and KOTH timer
     `AddOutput`s.
   - `tf_logic_koth` does not exist.
   - The KOTH clock inputs are ignored.
   - `tf_logic_competitive` never gets its pre-round lock and unlock.
   - The control point HUD is a numbered box.
7. **KOTH clocks are real `team_round_timer` entities** named
   `zz_blue_koth_timer` and `zz_red_koth_timer`, as TF2 creates them
   (`CKothLogic::InputRoundSpawn`). 7 maps `AddOutput` to them by name.
8. **Out of scope.** These TF2 logic classes are left unimplemented:
   - Other modes: player destruction, the CTF hybrid on cp_carrier
     (`item_teamflag`, `func_capturezone`, `func_flag_alert`), and
     `func_upgradestation`.
   - The minigames and wheel of doom.
   - VScript (`logic_script`, 10 maps).
   - Medieval mode's weapon restrictions. GMod has no TF2 classes or
     loadouts, so `tf_logic_medieval` logs once and does nothing.
9. **Build order.**
   - R (rounds) and C (capture) are built in parallel. They merge as a pair,
     back to back, because each deletes legacy code the other replaces.
   - K (KOTH), P (payload move) and M (small logic entities) then run in
     parallel.
   - Payload is checked in game after the R+C pair and again after P.

## 1. Gap analysis

### 1.1 What the representative maps need

Each map was dumped with `bsp_entities.py`.

**koth_viaduct, koth_harvest_final and koth_lakeside_final** (the KOTH pattern
in 44 maps):
- `tf_logic_koth` has `timer_length` 180 and `unlock_point` 30 (35 on
  lakeside).
- One `team_control_point` is neutral and unlocked in its keyvalues.
- One `trigger_capture_area` has a cap time of 3–8 s and `team_numcap` 1–2.
- There is no `team_round_timer` and no `game_round_win`.
- The area's `OnCapTeam1` goes to `tf_gamerules.SetRedKothClockActive` and
  `SetBlue/RedTeamRespawnWaveTime`. `OnCapTeam2` goes to
  `SetBlueKothClockActive` and the wave times.
- `logic_auto.OnMapSpawn` sets the goal strings and wave times.
- `tf_logic_competitive.OnSpawnRoomDoorsShouldLock` goes to
  `SetRoundRespawnFreezeEnabled 0`, and on viaduct also to the spawn
  triggers' `Disable` (`…Unlock` goes to `Enable`).

The win comes from `CTeamControlPointMaster::CheckWinConditions`: a team
that owns every point wins only when its KOTH clock is at 0 and
`TimerMayExpire()` holds.

| KOTH need | Sandcastle today |
|---|---|
| `tf_logic_koth` creates two paused 180 s clocks on RoundSpawn (`CKothLogic::InputRoundSpawn`) | missing class |
| On RoundActivate, every point gets `SetLocked unlock_point`, then `SetUnlockTime unlock_point` (`CKothLogic::InputRoundActivate`) | missing |
| Unlock countdown only while `RND_RUNNING`; `OnUnlocked` | the countdown timer exists in sv_controlpoint (moves to the model) |
| `SetRed/BlueKothClockActive`: resume own clock, pause the other (`CTFGameRulesProxy::InputSet*KothClockActive`) | ignored (`tf_gamerules.lua:833`) |
| Win gate: the owner of all points wins at its clock 0 and `TimerMayExpire` (`team_control_point_master.cpp:680`, `team_control_point_round.cpp:122`) | missing: a KOTH owner wins at once |
| Overtime: a clock at 0 holds while the enemy caps; `SetOvertime(true)` for timers shown in the HUD; nag | missing: `TimerMayExpire` only asks train watchers |
| No time limit timer in KOTH (`CreateTimeLimitTimer`) | missing |
| Every KOTH clock speaks its countdown (`CTeamRoundTimer::ClientThink`, `IsInKothMode`) | missing |
| `AddTimerSeconds` is silent in KOTH | missing |
| Capture sounds: `Hud.PointCaptured` plus `Announcer.Success`/`Failure` to each team (`CTFGameRules::PlaySpecialCapSounds`) | missing |
| HUD: two team clocks, the running one highlighted (`CTFHudKothTimeStatus`), point icon, unlock countdown 5..1 then `Announcer.AM_CapEnabledRandom` (`CControlPointCountdown::OnTick`) | missing |
| Timers named `zz_*_koth_timer` for maps' `AddOutput` (7 maps, via `OnMultiNewRound`) | missing, and `OnMultiNewRound` never fires |

**cp_granary and cp_badlands** (5CP):
- There are 5 points. Each team owns two by default (`point_index` 1,2 and
  4,5), and the neutral mid is index 3. No point sets previous points, so
  `tf_caplinear` uses the farthest-owned rule.
- There are no rounds.
- The timer is 600 s with `max_length` 600.
- `OnFinished` goes to a `game_round_win` with TeamNum 0, which is a
  stalemate or sudden death.
- A cap fires a relay that sends `AddTime 600`.
- `SetStalemateOnTimelimit 1` is set.
- Granary's areas have `team_spawn_2/3 = -3` and `team_numcap` 1–3.

| 5CP need | today |
|---|---|
| Linear capture: `TeamMayCapturePoint` with base points | works |
| Win by owning all (master without rounds) | works |
| Stalemate from `game_round_win 0`; sudden death with `mp_stalemate_enable` | works |
| Overtime: the timer holds at 0 while a point is being capped, plus a 0.1 s buffer (`CTFGameRules::TimerMayExpire`) | **missing** |
| `Announcer.Success`/`Failure` on a cap that does not win, with `score_style 0` | **missing** |
| Capture sounds `Hologram.Start/Move/Interrupted/Stop` unless spawnflag 8 (`CTeamControlPoint::CaptureStart/End/Interrupted`) | **missing** |
| Point HUD: owner, lock, progress, cappers against required, blocked, which team may cap, and the local player's capture panel reasons (`CControlPointProgressBar`) | numbered box only |

**cp_dustbowl** (A/D with stages):
- There is no `tf_gamerules`.
- There are 3 `team_control_point_round`s (priorities 100/50/25, restrict 2)
  with 2 points each. Each point's BLU previous point is itself, or the
  stage's first point.
- The master has `switch_teams 1`, `score_style 1` and `play_all_rounds 1`.
- The timer is 270 s with a 60 s setup. `OnFinished` goes to
  `game_round_win` (RED, switch).
- `OnCapTeam2` goes to `AddTime 270`, goal strings (to the name
  `tf_gamerules`, which no entity has), cameras and doors.

| A/D need | today |
|---|---|
| Rounds run at all | **missing** (no `tf_gamerules`: gap 0.1) |
| Stages chosen by priority, a mini-round win without map reset, the next stage's setup | works once rounds run |
| Time added on capture; `AddTeamTime` announcer | works; the notice is generic text |
| The defenders win at `OnFinished` only when no capture is in progress | **missing** (`TimerMayExpire`) |
| Goal strings sent to `tf_gamerules` by classname | works once the proxy exists |

**cp_gorge and cp_gravelpit** (single-stage A/D, no `tf_gamerules`):
- On gorge, the master has `cpm_restrict_team_cap_win 2`, the points' cap
  times are 6/30 s, and a cap on area 2 sends `AddTime 480`.
- On gravelpit, A and B are each self-previous, and C needs A (BLU). BLU's
  areas have `team_spawn_3 -3`. Caps go to relays that send
  `AddTeamTime "3 180"`.
- Both have a 60 s setup; the timer is resumed by a relay 60 s in.

Needs: rounds running (gap 0.1), overtime, the HUD's `caplayout "2, 0 1"`
(two rows), and the capture-sound and success/failure lines.

**cp_steel** (multi-path A/D):
- Five points have per-team previous points. E needs itself, D needs C,
  and so on.
- Area cap times are 16–35 s, and RED's `team_numcap` is 0 (clamped to 1).
- The master has `caplayout "4, 0 1 2 3"`.
- Relays send `SetOwner 3` to A–D ("early finish").
- `logic_auto.OnMultiNewRound` sends `AddBlueTeamRespawnWaveTime -6`.

Needs: `OnMultiNewRound` (gap 3), `SetOwner` from a relay (non-player
caller, so no capture sound), the layout, and overtime.

**cp_degrootkeep** (medieval):
- There is a `tf_logic_medieval`.
- A `tf_logic_cp_timer` watches `control_point_3` for 60 s. On
  `OnCountdownStart` it sets BLU's wave time to 0. On `OnCountdownEnd` it
  resets points 1–2 to RED and sets BLU's wave time to 4.
- The timer's `OnFinished` goes to `master.SetWinner 2`.

Needs:
- `tf_logic_cp_timer` (`CCPTimerLogic`). It starts when BLU may cap point 3.
  At expiry it waits for no capture in progress, then fires `OnCountdownEnd`.
  It blocks `TimerMayExpire` while BLU may cap. Its 15/10/5-second flags
  exist in the SDK but fire nothing, so they are not ported as outputs.
- The point HUD's countdown under point 3.
- `tf_logic_medieval` stubbed.

### 1.2 Gaps shared by every mode

| # | gap | evidence |
|---|---|---|
| G1 | 14 maps have no `tf_gamerules`: cp_5gorge, cp_cloak, cp_dustbowl, cp_egypt_final, cp_fastlane, cp_freight_final1, cp_gorge, cp_gorge_event, cp_gravelpit, cp_junction_final, cp_manor_event, cp_mountainlab, cp_well, koth_sawmill | `WETSAND.Active()` is set only by `tf_gamerules:Initialize` |
| G2 | `TimerMayExpire` = train watchers only; TF2 also refuses while any point has a capping team, 0.1 s after, and while a `tf_logic_cp_timer` holds | `sv_rounds.lua:63`, `CTFGameRules::TimerMayExpire` |
| G3 | `logic_auto` fires `OnMultiNewRound` only when `g_pGameRules->InRoundRestart()` (`sdk/server/logicauto.cpp:111`), which nothing in Sandcastle can make GMod's gamerules report (integrator confirms with `developer 2` on cp_steel), so after `game.CleanUpMap` a `logic_auto` fires `OnMultiNewMap` again and never `OnMultiNewRound`; TF2 fires `OnMultiNewRound` after each full reset (its first round follows a reset too) | `CLogicAuto::Think`; 56 maps |
| G4 | `tf_logic_competitive`: `OnSpawnRoomDoorsShouldLock` at pre-round start and `…Unlock` at its end (`CTFGameRules::PreRound_Start/End`) are never fired | 15 maps |
| G5 | `PlaySpecialCapSounds` missing | `trigger_area_capture.cpp:888` |
| G6 | capture sounds missing | `team_control_point.cpp:106–120, 505–560` |
| G7 | the control point HUD lacks the TF2 objective resource's fields | `sdk/client/c_team_objectiveresource.cpp` |
| G8 | `GetBaseControlPoint` with mini-rounds uses only in-round points; ours uses all | `team_control_point_master.cpp:1070` |
| G9 | time added is a generic `WETSAND.Announce("+m:ss")`; TF2 flashes it by the timer | `team_round_timer.lua:243` |
| G10 | `tf_gamerules`, `sv_rounds`, `sv_controlpoint`, `sv_payload` and the round HUD are always loaded, and rules live in entities | the lua skill's layering |

### 1.3 Logic entities in the census

Run `.devtools/bin/map_census.py koth_ cp_` (101 maps). Classes neither
Sandcastle nor GMod's `server.dll` provides:

| class | maps | decision |
|---|---|---|
| tf_logic_koth | 45 (44 koth + cp_sulfur) | **K** implements |
| game_intro_viewpoint | 11 | out: the new-player map tour; not placed, no I/O used |
| logic_script | 10 | out: VScript (not a TF2-only class; GMod drops it) |
| trigger_ignite_arrows | 6 | out: no Huntsman arrows in GMod; no I/O used |
| trigger_ignite | 3 | **M** implements (`CTriggerIgnite`, `sdk/server/tf/tf_triggers.cpp`) |
| tf_logic_medieval | 3 | **M** stub (logs once) |
| tf_logic_cp_timer | 2 | **M** implements |
| func_achievement | 2 | out: achievements (econ) |
| prop_soccer_ball, wheel_of_doom, editor_text | 2 each | out |
| tf_logic_on_holiday | 1 | **M** implements (`Fire` → `IsHalloween`…, via the holiday controller) |
| filter_tf_condition | 1 | **M** implements (P2 inside M) with `foundation.players.COND` |
| tf_logic_player_destruction, tf_logic_hybrid_ctf_cp, item_teamflag, func_capturezone, func_flag_alert, func_upgradestation, tf_base_minigame, trigger_apply_impulse, func_detail_blocker | 1 each | out (other modes, MvM, compile-only) |

`server.dll` names these, so they are GMod's: `team_control_point`,
`info_player_teamspawn`, `trigger_catapult` (`CTriggerCatapult`, 4 KOTH
maps), `trigger_remove`, `point_template`, and `game_text_tf` (listed
beside `CGameText`, 6 cp maps). The integrator confirms `game_text_tf` in
game (section 9.3). No koth_ or cp_ map uses `tf_logic_arena`.

The pass-3 classes `tf_halloween_gift_spawn_location`, `func_croc`,
`tf_generic_bomb`, `tf_point_weapon_mimic`, `headless_hatman`,
`eyeball_boss` and `merasmus` are already done.

### 1.4 I/O the maps send to objective entities (all 101 maps)

| target | inputs (maps) | handled after pass 4 by |
|---|---|---|
| tf_gamerules | SetRed/BlueTeamGoalString 73, Set*TeamRespawnWaveTime 73, **SetBlue/RedKothClockActive 43**, Set*TeamRole 21, SetStalemateOnTimelimit 16, SetRoundRespawnFreezeEnabled 13, PlayVO* 7/3/3, SetRequiredObserverTarget 4, AddBlueTeamRespawnWaveTime 1, SetMapForcedTruceDuringBossFight 1, SetCustomUpgradesFile 1, HandleMapEvent 1 | R (KOTH clocks forward to the rounds controller) |
| team_round_timer | AddTime 39, AddTeamTime 13, Resume 8, SetTime 5, Enable 2, Pause 2, Restart 1, Disable 1, ShowInHUD 1 | R |
| game_round_win | RoundWin 44 | R |
| team_control_point_master | SetWinner 13 | C |
| team_control_point | SetOwner 7, SetLocked 6, SetUnlockTime 3, Enable/Disable 2 (TF2 has neither: ignored as in TF2), HideModel/ShowModel 1 | C |
| trigger_capture_area | Disable 3, Enable 2, CaptureCurrentCP 1, SetTeamCanCap 1 | C |
| zz_red/blue_koth_timer | AddOutput 7/6 | engine, on K's timers |

| source | outputs listened to (maps) |
|---|---|
| trigger_capture_area | OnCapTeam2 95, OnCapTeam1 71, OnEndCap 23, OnStartCap 2, OnBreakCap 2, OnNumCappersChanged(2) 1 each |
| team_round_timer | OnFinished 56, OnSetupFinished 36, OnSetupStart 6, On5MinRemain 5, other marks 1–2 |
| team_control_point | OnCapTeam2 14, OnCapTeam1 9, OnUnlocked 3, OnOwnerChangedToTeam2 1, OnCapReset 1 |
| team_control_point_master | OnWonByTeam1/2 11 |
| team_control_point_round | OnStart 5, OnWonByTeam2 2, OnEnd 1 |
| tf_gamerules | OnWonByTeam1/2 6 |
| tf_logic_competitive | OnSpawnRoomDoorsShouldLock 15, …Unlock 12 |
| tf_logic_cp_timer | OnCountdownStart 2, OnCountdownEnd 2 |
| logic_auto | OnMapSpawn 101, **OnMultiNewRound 56**, OnMultiNewMap 13, OnNewGame 6 |

## 2. Architecture

### 2.1 Systems and parts (models, `foundation/`, pure)

| system | parts | model it holds |
|---|---|---|
| `foundation.rounds` (R) | `.state` (exists); `.timer` (CTeamRoundTimer); `.text` (win and stalemate panels, `Localize`, time-added text); mode strategies `.control_points` (R), `.koth` (K), `.payload` (P) | a `Round` (gamerules state machine, wins, sudden death, limits, respawn waves, setup and overtime, `TimerMayExpire`, played-round history, the mode) and the `Mode` template |
| `foundation.capture` (C) | `.area` (today's `foundation.capture`, moved); `.master` (the master and its mini-rounds); `.point_timer` (M, `CCPTimerLogic`) | a `PointSet` (every point: owner, lock, unlock time, capture order, groups, capture-panel reasons, HUD layout) |
| `foundation.payload` (unchanged) | `.race` | P updates its `TeamOwnsAllPoints`/`IsPlayable`/`FinalPoint` callers to the master (section 5.5) |

The functions `foundation.rounds` exports today move:

| today | moves to | by |
|---|---|---|
| `TeamOwnsAllPoints`, `RoundWinner`, `RoundPlayable`, `PlayableCount`, `StageOf`, `ChooseRound`, `RoundsRemaining` | `foundation.capture.master` | C |
| `Ranks`, `BaseControlPoint`, `FarthestOwnedControlPoint`, `TeamMayCapturePoint`, `NO_POINT`, `CP_WARN` | `foundation.capture` | C |
| `ArmTimerOutputs`, `NextTimerOutput`, `TimerOutputName`, `TimeAfterSetup`, `ClampAdd` | `foundation.rounds.timer` (internals) | R |
| `ArmClientWarnings`, `NextClientWarning`, `ChooseActiveTimer` | `foundation.rounds.timer` (exported) | R |
| `WinPanel`, `StalematePanel`, `Localize` | `foundation.rounds.text` | R |
| `WINREASON`, `STALEMATE`, `RESTRICT_NEITHER`, `StalemateOutcome`, `WaveTime`, `TimeLeft`, `WinLimitReached`, `MaxRoundsReached`, `CanChangeLevelForTimeLimit`, `TimeLimitReached`, `TimelimitWinner`, `ShouldRewardTeam`, `AddPlayedRound` | stay in `foundation.rounds`, used by the `Round` model | R |

### 2.2 Features (controllers and views)

| feature | loaded by (entity `Initialize`) | controller owns | view (client) |
|---|---|---|---|
| `rounds` (R) | tf_gamerules, team_round_timer, game_round_win, tf_logic_competitive, and every other feature below (which requires it) | the `Round`; a `Timer` per `team_round_timer`; the HUD timer; the proxy; the mode; round listeners; timer holds; team clocks; the objective port; `logic_auto` round outputs; competitive doors; all `wetsand_round_*` and `wetsand_timer_*` keys | the timer (label, time-added flash), pre-round, respawn countdown, announcements, round panel (stage, scores, goal), win, sudden death and game-over panels, notices, announcer countdown, overtime line and bell. Replaces cl_announcer, cl_rounds, and cl_hud's timer, preround, respawn and announcement parts |
| `capture` (C) | trigger_capture_area, team_control_point_master, team_control_point_round | the `PointSet`; an `Area` per trigger; the `Master`; the `team_control_point` input hook; point models; capture sounds; scoring; notices; `wetsand_point_*` keys | point icons (layout, owner, lock, unlock countdown and its announcer, progress, cappers, blocked, can-cap marks, cp timer countdown), the local player's capture panel |
| `koth` (K) | tf_logic_koth | the KOTH logic model; the two clock entities; `wetsand_koth_*` keys | the two team clocks, and the clocks' countdown speech |
| `payload` (P) | team_train_watcher, tf_logic_multiple_escort | today's sv_payload (cart speed scale, race, final point, cart HUD keys) | cart bars (from cl_hud), race sounds (cl_payload) |

`capture`, `koth` and `payload` call `WETSAND.Feature("rounds")` when they
load; `koth` and `payload` also call `WETSAND.Feature("capture")`. No
`sh.lua` is needed.

### 2.3 Interfaces

#### Mode (the strategy `foundation.rounds` declares)

`Rounds.Mode` is the template, with every default. A variant is
`Rounds.Mode:Extend(name)` plus overrides.

| member | default (`Mode`) | control_points | koth (extends control_points) | payload |
|---|---|---|---|---|
| `NAME` | "none" | "control_points" | "koth" | "payload" |
| `PRIORITY` | 0 | 1 | 3 | 2 |
| `HUD` | `HUD_NONE` | `HUD_CONTROL_POINTS` | `HUD_KOTH` | `HUD_PAYLOAD` |
| `CREATES_TIME_LIMIT_TIMER` | true | true | false | true |
| `ANNOUNCES_TIME_ADDED` | true | true | false | true |
| `SCORE_CHIME_TO_ALL` (`Hud.EndRoundScored` to all, else the capping team) | false | false | false | true |
| `MayWinByPoints(team, q) -> bool` (q = `{ clockRemaining = n or nil, timerMayExpire }`) | true | true | `clockRemaining == nil or (clockRemaining <= 0 and timerMayExpire)` | true |
| `CapSounds(capTeam, q) -> { {team, sound}... }` (q = `{ wouldWinGame, scorePerRound }`) | {} | if `scorePerRound and not wouldWinGame`: capTeam `Announcer.Success`, the other game team `Announcer.Failure` | for each game team `Hud.PointCaptured`, then Success/Failure | {} |
| `RoundWinLines(winner, fullRound, race) -> { [team] = line }` | {} | {} | {} | `race and Race.OutcomeLines(winner, fullRound) or {}` |

Constants in `foundation.rounds`:
- `HUD_NONE=0, HUD_CONTROL_POINTS=1, HUD_KOTH=2, HUD_PAYLOAD=3`
- `PHASE_SPAWN="spawn", PHASE_ACTIVATE="activate", PHASE_ROUND_END="round_end"`
- `LISTEN_TIMERS=10, LISTEN_CAPTURE=20, LISTEN_LOGIC=30`: the listener
  order. It reproduces TF2's RoundSpawn/RoundActivate order: timers, then
  the master and points, then logic entities.

#### Objective port (implemented by the capture controller, faked in tests)

`Rounds.OBJECTIVE_METHODS` lists the port's methods:
- `PlayingMiniRounds() -> bool`
- `NumPlayable() -> n`
- `PlayAllRounds() -> bool`
- `RoundsRemaining(team) -> n`
- `ScorePerRound() -> bool` (score_style 0)
- `SuddenDeathWin(team)`: the master's `SetWinnerAndForceCaps`

With no objective bound, the rounds controller uses `Rounds.NO_OBJECTIVE`:
false, 0, false, 0, true, and nil. Nil means sudden death ends with
`SetWinningTeam(OPPONENTS_DEAD)`. `tests/fake_objective.lua` implements
the port, and a contract test checks it against `OBJECTIVE_METHODS`.

#### Round model (R)

```lua
local round = Rounds.New(settings)       -- settings below; state PREGAME
round:Configure(settings)                -- the controller refreshes convars each think
round:SetMode(mode) -> changed           -- keeps the higher PRIORITY
round:Mode()
round:State()
round:Think(now, world) -> effects
round:SetWinningTeam(now, winner, reason, forceMapReset, switchTeams, dontAddScore, objective) -> effects
round:SetStalemate(now, reason, forceMapReset, switchTeams) -> effects
round:RestartRound(now) -> effects
round:Halt(now) -> effects
round:Unhalt()
round:Halted()
round:PointsMayBeCaptured()              -- (RND_RUNNING or STALEMATE) and not in setup
round:InSetup()
round:SetSetup(b) -> changed
round:InOvertime()
round:SetOvertime(b) -> changed
round:TimerMayExpire(now, holds) -> bool -- holds = { capturing, other }; capturing arms a 0.1 s buffer
round:MayWinByPoints(team, q)            -- delegates to the mode
round:AddPlayedRound(name)
round:History() -> { previous = {…}, first = name }
round:SetFirstRoundPlayed(name)
round:SetTeamWaveTime(team, s)
round:AddTeamWaveTime(team, s)
round:SetAdminWaveTime(team, s or nil)
round:TeamWaveTime(team)
round:WaveMaxLength(team, teamSize, scale)
round:NextRespawn(team, deathTime, teamSize) -> time
round:WaveDue(team, now, teamSize) -> bool   -- advances the team's next wave
round:MayRespawn(deathTime, now) -> bool     -- CTFGameRules::GetMinTimeWhenPlayerMaySpawn
round:SetRespawnsDisabled(b)
round:RespawnsDisabled()
```

`settings` = `{ respawnWaveTime, bonusRoundTime, enableRoundWaitTime,
stalemateEnable, stalemateTimelimit, winlimit, maxrounds, timelimit,
matchEndAtTimelimit, chattime, mapResetTime }`, in TF2's units.

`world` = `{ havePlayers, teams = { [RED] = { players, alive }, [BLUE] = … },
scores = { [RED], [BLUE] }, stalemateTimerLeft = n or nil, timerMayExpire,
mapHasActiveTimer, objective }`.

Effects are plain tables `{ kind = …, … }`, applied by the controller in
order:

| kind | fields | controller does |
|---|---|---|
| `state` | from, to | `SetGlobal2Int("wetsand_round_state")` |
| `output` | name, value | `proxy:TriggerOutput(name, proxy, value)` |
| `balance_teams` | | `WETSAND.BalanceTeams(false)` |
| `cleanup` | | `game.CleanUpMap(false, CLEANUP_KEEPS)`, with `OnMultiNewMap` suppressed (5.1) |
| `new_round_outputs` | | fire `OnMultiNewRound` on every `logic_auto` |
| `round_spawn` / `round_activate` | | run the `PHASE_SPAWN` / `PHASE_ACTIVATE` listeners in order, then `hook.Run("WetsandRoundSpawn")` / `("WetsandRoundActivate")` |
| `previous_round_end` | | run `PHASE_ROUND_END` listeners (the master's `OnEnd`) |
| `activate_timers` | | `ActivateTimers()` |
| `time_limit_timer` | seconds | only if `mode.CREATES_TIME_LIMIT_TIMER` (the model already checks) |
| `switch_teams` | | swap RED/BLU players and scores |
| `respawn_all` | | spawn everyone but spectators |
| `respawn_team` | team | spawn that team's dead whose `MayRespawn` holds |
| `doors_lock` / `doors_unlock` | | every `tf_logic_competitive`'s lock/unlock output |
| `hook` | name, args | `hook.Run` (`WetsandRoundActive`, `WetsandRoundWin`) |
| `score` | team, points | `team.AddScore` |
| `publish_win` | winner, reason, fullRound | the win keys, with `objective:RoundsRemaining(winner)` |
| `win_song` | winner | `Game.YourTeamWon`/`Lost`/`Stalemate`, plus `mode.RoundWinLines` |
| `sudden_death` | reason | `wetsand_stalemate_reason` and `Game.SuddenDeath` |
| `hide_timers` / `restore_timers` | | as `HideActiveTimer`/`RestoreActiveTimer`; the restore also re-shows team clocks (`CTFGameRules::RestoreActiveTimer`) |
| `stalemate_timer` | seconds | `CreateTimer(nil, seconds)`; removed on leaving `STALEMATE` |
| `stalemate_winner` | team, forceMapReset | `objective.SuddenDeathWin(team)` when not `forceMapReset` and the port has one, else `SetWinningTeam(OPPONENTS_DEAD)` |
| `intermission` | reason, until | freeze everyone, `wetsand_game_over_reason` |
| `changelevel` | | `RunConsoleCommand("changelevel", game.GetMap())` |
| `unfreeze` | | unfreeze everyone |

The state machine ports `tf_gamerules.lua` exactly. It changes only in
these three ways, each from the SDK:

- PREROUND entry emits `doors_lock`, and leaving PREROUND emits
  `doors_unlock` (G4). BETWEEN_RNDS entry emits `doors_unlock`, as today.
- Every full-reset `RoundRespawn` emits `new_round_outputs` after
  `round_activate`, including the first round, which needs no `cleanup`
  (G3).
- `time_limit_timer` is emitted only when the mode creates one.

#### Timer model (R, `foundation.rounds.timer`)

```lua
local timer = Timer.New{ length = 600, maxLength = 0, setupLength = 0, startPaused = true,
	showInHud = true, autoCountdown = true, resetTime = false, startDisabled = false, now = t }
timer:TimeRemaining(now)
timer:Paused()
timer:Disabled()
timer:InSetup()
timer:ShowInHud()
timer:AutoCountdown()
timer:Serial()
timer:SetTimeRemaining(now, s) -> events
timer:Pause(now)
timer:Resume(now)
timer:Enable(now)
timer:Disable(now)
timer:Restart(now)
timer:SetMaxLength(now, s)
timer:SetSetupLength(now, s)
timer:SetShowInHud(b)                    -- CTeamRoundTimer::SetShowInHud: no HUD-timer choice
timer:SetAutoCountdown(b)
timer:RoundSpawn(now) -> events
timer:FinishSetup(now) -> events
timer:AddSeconds(now, s, team, q) -> events, added
timer:Think(now, q) -> events
```

- `AddSeconds`'s `q` = `{ roundRunningOrWon, isHud, roundWon, inStalemate,
  announces }`.
- `Think`'s `q` = `{ mayExpire, isHud, roundWon, overtime, nagEnabled,
  random }`.

Events:
- `{ kind = "output", name }`: OnSetupStart, OnRoundStart, OnSetupFinished,
  OnFinished, and the marks.
- `{ kind = "setup", value }`
- `{ kind = "overtime", value }`: only when `showInHud`, as
  `CTeamRoundTimer::RoundTimerThink` does.
- `{ kind = "nag" }`
- `{ kind = "length_changed" }`: the serial bumps.
- `{ kind = "time_added", team, seconds }`: only when `q.announces` and
  `isHud` and not `roundWon`/`inStalemate`.

#### PointSet (C, `foundation.capture`)

```lua
local set = Capture.New{ caplinear = true, points = {
	{ id, index, defaultOwner, startLocked, group, warnOnCap, warnSound, printName, spawnflags,
	  previous = { [RED] = { ids }, [BLUE] = { ids } } } } }
set:Ids()                                -- rank order, TF2's renumbering (FindControlPoints)
set:Rank(id)                             -- 0-based
set:Index(id)
set:Owner(id)
set:DefaultOwner(id)
set:Group(id)
set:Locked(id)
set:UnlockAt(id)
set:PrintName(id)
set:Warn(id)
set:Spawnflags(id)
set:SetOwner(id, team, cause) -> events  -- cause: CAUSE_CAPTURE, CAUSE_PLAYER_INPUT, CAUSE_INPUT, CAUSE_FORCE
set:SetLocked(id, locked) -> events
set:SetUnlockTime(id, seconds, now) -> events
set:Tick(now, roundRunning) -> events    -- CTeamControlPoint::UnlockThink
set:RoundActivate() -> events            -- InputRoundActivate: round_start_owned, then unlocked for unlocked points
set:TeamOwnsAll(ids, overrideId, overrideTeam) -> team
set:TeamMayCapture(id, team, q) -> bool  -- q = { playingMiniRounds, inRound = { [id] = true } or nil, base = rank }
set:CannotCapReason(id, team, q) -> REASON_*
Capture.Layout(caplayout, count) -> rows -- "4, 0 1 2 3" -> { {4}, {0,1,2,3} }; "" -> one row in rank order
```

- `CannotCapReason`'s `q` adds `{ pointsMayBeCaptured, blocked, capping,
  cappers, required, reverting }`.
- `SetOwner` events: `{ kind = "owner", id, old, team, sounding }`, where
  `sounding` is true for CAPTURE and PLAYER_INPUT.
- `SetLocked` and `SetUnlockTime` events: `{ kind = "unlocked", id }` and
  `{ kind = "unlock_time", id, at }`.

Constants:
- `NO_POINT=-1`, `MAX_PREVIOUS_POINTS=3`, `CP_WARN`
  (`NORMAL/FINALCAP/NO_ANNOUNCEMENTS`)
- `SF_HIDE_MODEL=2`, `SF_NO_CAP_SOUNDS=8` (`team_control_point.h`)
- the `CAUSE_*` constants above
- `SOUND_START="Hologram.Start"`, `SOUND_END="Hologram.Stop"`,
  `SOUND_PROGRESS="Hologram.Move"`, `SOUND_INTERRUPTED="Hologram.Interrupted"`
  (the `point_capture_*_sound` defaults)
- `REASON_NONE=0, REASON_NOT_NOW=1, REASON_BLOCKING=2, REASON_REVERTING=3,
  REASON_OWNED=4, REASON_OWN_POINT=5, REASON_LINEAR=6, REASON_BLOCKED=7,
  REASON_CANNOT=8, REASON_WAITING=9`
- `REASON_TOKEN[reason]`: `#Team_Capture_NotNow`, `#Team_Blocking_Capture`,
  `#Team_Reverting_Capture`, `#Team_Capture_Owned`, `#Team_Capture_OwnPoint`,
  `#Team_Capture_Linear`, `#Team_Capture_Blocked`, `#Team_Cannot_Capture`,
  `#Team_Waiting_for_teammate`. This follows
  `CControlPointProgressBar::UpdateBarText`,
  `sdk/client/hud_controlpointicons.cpp:1550–1645`, in its order.

#### Area (C, `foundation.capture.area`)

Today's `foundation.capture`, moved unchanged: `New`, `Step`,
`CaptureCurrent`, `Break`, `Progress`, `TotalTime`, `SpawnAdjustments` and
`BLOCKSTYLE_*`. It adds `PointSounds(event, spawnflags) -> { play = name or nil,
loop = name or nil, stopLoop = bool }`, from `CaptureStart/End/Interrupted`:

| event | sounds |
|---|---|
| start | Start, then loop Progress |
| blocked true | loop Interrupted |
| blocked false | Start, then loop Progress |
| end | stop, then End |
| break | stop |

With `SF_NO_CAP_SOUNDS` nothing plays.

#### Master (C, `foundation.capture.master`)

```lua
local master = Master.New{ restrict, switchTeams, scoreStyle, playAllRounds, partialCapRate,
	capLayout, disabled, rounds = { { name, priority, restrict, printName, points = { ids } } } }
master:PlayingMiniRounds()
master:Current()                         -- round name or nil
master:IsInRound(id)
master:InRound()                         -- { [id] = true } or nil
master:ChooseRound(set, history, random) -> name or nil   -- GetControlPointRoundToPlay
master:EndRound() -> name or nil
master:Winner(set) -> team or nil, roundName or nil       -- CheckWinConditions minus the KOTH gate
master:WinArgs(set) -> forceMapReset, switchTeams
master:SetWinnerArgs(team, set) -> { stalemate, forceMapReset, switchTeams }
master:WouldNewOwnerWin(set, id, team)
master:RoundsRemaining(team, set)
master:NumPlayable(set)
master:Stage(set) -> stage, count, printName
master:BaseControlPoint(set, team) -> rank or NO_POINT   -- in-round points only with mini-rounds (G8)
master:ScorePerCapture()
master:Enable()
master:Disable()
master:Active()
```

Constants: `SCORE_PER_ROUND=0, SCORE_PER_CAPTURE=1`.

#### KOTH (K, `foundation.rounds.koth`)

The mode above, plus the logic model:

```lua
local koth = Koth.New{ timerLength = 180, unlockPoint = 30 }
koth:Clocks() -> { { team = BLUE, name = "zz_blue_koth_timer", length }, { team = RED, name = "zz_red_koth_timer", length } }
koth:PointLock() -> { locked = unlockPoint > 0, unlockTime = unlockPoint > 0 and unlockPoint or nil }
Koth.ClockActive(team) -> resume, pause  -- (team, enemy)
```

Constants: `TIMER_LENGTH_DEFAULT=180`, `UNLOCK_POINT_DEFAULT=30` (the
`CKothLogic` constructor), `CLOCK_NAME`.

#### Point timer (M, `foundation.capture.point_timer`)

```lua
local pt = PointTimer.New{ length = 60, team = BLUE }
pt:Think(now, q) -> events               -- q = { teamMayCapture, capping, roundWon }
pt:MayExpire(teamMayCapture)             -- false while the team may capture
pt:EndTime()                             -- nil when idle
```

- Events: `{ kind = "start", endTime }` (OnCountdownStart) and
  `{ kind = "end" }` (OnCountdownEnd, only once nobody is capping).
- Constants: `THINK_INTERVAL=0.15`, `LENGTH_DEFAULT=60`.

### 2.4 Controller methods other packages call

**rounds** (R):
- Binding and timers:
  - `BindProxy(ent)`
  - `Proxy()`
  - `BindTimer(ent, kv) -> timer`
  - `TimerOf(ent)`
  - `HudTimer() -> ent or nil`
  - `SetActiveTimer(ent or nil)`
  - `CreateTimer(name, seconds, { showInHud, hudChoice })`
  - `TimerInput(ent, name, value)`
- Mode, phases and holds:
  - `SetMode(mode)`
  - `Mode()`
  - `AddRoundListener(phase, order, fn)`
  - `AddTimerHold(name, fn, isCapture)`: `fn()` returns true while it holds
    the clock.
  - `TimerMayExpire()`
  - `MayWinByPoints(team)`
  - `SetObjective(port)`
- Team clocks:
  - `SetTeamClock(team, ent or nil)`
  - `TeamClock(team)`
  - `ActivateTeamClock(team)`: a no-op with no clocks, as in TF2.
- Round state:
  - `State()`
  - `PointsMayBeCaptured()`
  - `InSetup()`
  - `InOvertime()`
  - `SetWinningTeam(winner, reason, forceMapReset, switchTeams, dontAddScore)`
  - `SetStalemate(reason, forceMapReset, switchTeams)`
  - `AddPlayedRound(name)`
  - `History()`
  - `SetFirstRoundPlayed(name)`
- Sounds and notices:
  - `CapSounds(capTeam, wouldWinGame, scorePerRound)`
  - `SoundTo(players, name)`
  - `PlayersNotOn(team)`
  - `Notice(text, team)`
- The gamerules surface the `tf_gamerules` binding forwards:
  - `OnPlayerDeath(ply)`
  - `Halt()`
  - `Unhalt()`
  - `Halted()`
  - `RestartRound()`
  - `RespawnsDisabled()`
  - `SetRespawnsDisabled(b)`
  - `SetAdminRespawnWaveTime(team, s)`
  - `TeamRespawnWaveTime(team)`
  - `GetRespawnWaveMaxLength(team, scale)`
  - `ProxyInput(name, value)`

**capture** (C):
- Binding:
  - `BindMaster(ent, kv)`
  - `BindRound(ent, kv)`
  - `BindArea(ent, kv)`
  - `AreaThink(ent)`
  - `AreaInput(ent, name, value)`
  - `MasterInput(ent, name, value)`
  - `RoundInput(ent, name, value)`
- Point queries (by entity):
  - `Owner(point)`
  - `Index(point)`
  - `Rank(point)`
  - `Points()` (ordered point entities)
  - `IsInRound(point)`
  - `TeamMayCapture(point, team)`
  - `IsCapturing(point)`
  - `CappingTeam(point)`
- Rounds and points:
  - `CurrentRound() -> round ent or NULL`
  - `RoundPoints(roundEnt)`
  - `ForceOwner(point, team)`
  - `FinalPointInMap(point)`: moved from sv_payload.
- For other features:
  - `SetHudHidden(point, bool)`: payload hides cart points.
  - `SetPointTimer(point, endTime or nil)`: M's cp timer.
  - `SetPointLocked(point, locked)` and `SetPointUnlockTime(point, s)`:
    K's unlock.

**koth** (K):
- `BindLogic(ent, kv)`
- `LogicInput(ent, name, value)`

**payload** (P):
- `CartSpeedScale()`
- `SetCartSpeedScale(s)`
- `HasMultipleTrains()`
- `BindWatcher(ent)`
- `BindEscort(ent)`

### 2.5 Networked state

Global2 keys, snake_case, `wetsand_` prefix, named for what they hold.

- **rounds** keeps every key it has today:
  - `wetsand_rounds_active`, `wetsand_round_state`, `wetsand_round_in_setup`,
    `wetsand_round_overtime`
  - `wetsand_round_winner`, `wetsand_round_win_reason`,
    `wetsand_round_full_round`, `wetsand_rounds_remaining`
  - `wetsand_preround_end_time`, `wetsand_stalemate_reason`,
    `wetsand_game_over_reason`
  - `wetsand_round_goal_<team>`, `wetsand_round_role_<team>`
  - `wetsand_mini_round_{stage,count,name}` (published through the capture
    controller)
  - `wetsand_gameplay_halted`
  - `wetsand_timer_{shown,paused,time_left,end_time,in_setup,auto_countdown,serial}`

  It adds `wetsand_round_hud_type` (`mode.HUD`).
- **Net messages:**
  - `wetsand_pa_sound_file`, `wetsand_pa_announce_text` and
    `wetsand_round_notice_show` keep their names and formats.
  - New: `wetsand_timer_time_added` (UInt team, Int seconds) replaces the
    `"+m:ss"` announcement (G9).
- **capture** publishes:
  - `wetsand_point_count`
  - `wetsand_point_layout` (the master's `caplayout`)
  - for each rank r (1-based), `wetsand_point_<r>_`:
    - `owner`, `locked`, `unlock_time`
    - `capping`, `progress`, `cappers`, `required`, `blocked`
    - `red_can_cap`, `blue_can_cap`, `in_round`, `hidden`
    - `name` (the print name), `timer_end`

  It publishes at 10 Hz while `WETSAND.Active()`. Player NW2 values
  `wetsand_capture_point` (the rank the player stands in; 0 for none) and
  `wetsand_capture_reason` (`REASON_*`) drive the capture panel.
  sv_payload's `wetsand_capture_*` keys and their drawer are removed (C).
- **koth** publishes `wetsand_koth_clock_<team>_{time_left,end_time,paused}`
  for teams 2 and 3.
- **payload** keeps `wetsand_cart_*` unchanged.

## 3. Migration of the legacy code (payload working at every merge)

| legacy file | fate | package |
|---|---|---|
| `wetsand/sv_rounds.lua` | into the rounds controller (timer registry, setup and overtime, switch teams, notices, `SoundTo`); deleted | R |
| `wetsand/cl_rounds.lua`, `wetsand/cl_announcer.lua` | into the rounds view; deleted | R |
| `wetsand/cl_hud.lua` | R moves timer, preround, respawn and announcement to the rounds view, deletes `DrawCaptures`, and leaves only the carts behind a `SandcastleHUDPaint` hook. P moves the carts to the payload view and deletes the file | R, then P |
| `cl_init.lua` | drops `WETSAND.DrawHUD()` and `WETSAND.AnnouncerThink()` (views hook `SandcastleHUDPaint` and `Think`) | R |
| `wetsand/sh_core.lua` | gains `WETSAND.InSetup()` and `WETSAND.InOvertime()` readers of the Global2 keys, so aiwar and filters work on any map | R |
| `wetsand/sv_controlpoint.lua` | into the capture model and controller; deleted | C |
| `wetsand/sv_payload.lua` | C removes `PublishCaptures`, uses `capture:FinalPointInMap` / `TeamMayCapture` / `Owner` / `CurrentRound`, registers the watcher timer hold, and sets the payload-free parts it needs. P moves the rest to the payload controller and deletes it | C, then P |
| `wetsand/cl_payload.lua` | into the payload view; deleted | P |
| `entities/tf_gamerules.lua` | thin binding (forwards) | R |
| `entities/team_round_timer.lua`, `game_round_win.lua`, `tf_logic_competitive.lua` | thin bindings | R |
| `entities/team_control_point_master.lua`, `team_control_point_round.lua`, `trigger_capture_area.lua` | thin bindings (round keeps `:Points()` and `:GetName()` for sv_teams_spawn's hook) | C |
| `entities/team_train_watcher.lua` | `WETSAND.CapTeam`→`capture:Owner`, `FinalPointInMap`→`capture:FinalPointInMap` (C); `WETSAND.Payload`/`CartSpeedScale`→payload controller (P) | C, then P |
| callers of `WETSAND.CapTeam/PointIndex/ControlPoints/Master/TeamCanCapPoint/CurrentRound`: `sv_teams_spawn.lua`, `sv_spectate.lua`, `filter_activator_tfteam.lua`, `headless_hatman.lua` | call `WETSAND.Feature("capture")`'s methods | C |
| `features/editors/sv.lua` | `WETSAND.HudTimer`→`rounds:HudTimer()`, `timer.paused`→`timer:Paused()` (R); `WETSAND.CartSpeedScale`→payload controller (P) | R, then P |

States:
- **After R and C (merged back to back):** payload plays as today through
  the new rounds and capture features, with carts still drawn by the
  remaining `cl_hud.lua` and cart logic still in `sv_payload.lua`.
- **After P:** no legacy file is left.

## 4. Rules the models must reproduce (cite the C++ in comments)

- **Proxy.** When the rounds controller loads, it hooks `InitPostEntity`,
  or runs at once if that has passed. With no `tf_gamerules`, it
  `ents.Create`s one, `SetName("tf_gamerules")`s it, and spawns it.
  `WETSAND.Active()` becomes true when a proxy binds.
- **`logic_auto` (G3).** During the cleanup effect, an `EntityKeyValue`
  hook in the rounds controller returns `""` for `OnMultiNewMap` on
  `logic_auto`, so the engine's re-fire goes nowhere.
  `new_round_outputs` then fires each `logic_auto`'s recorded
  `OnMultiNewRound` (`WETSAND.FireOutput(ent, "OnMultiNewRound", ent)`) on
  the next tick, before an auto-removing one removes itself. This covers
  the first round too (no cleanup; `OnMultiNewMap` already fired at load,
  as in TF2).
- **`TimerMayExpire` (G2).** It is false while any capture area is
  capturing (capture's hold, `isCapture = true`), for 0.1 s after
  (`m_flCapInProgressBuffer`), while any cp timer holds, and while any
  train watcher holds (payload's hold).
- **KOTH.** `tf_logic_koth` `RoundSpawn` (listener `LISTEN_LOGIC`) creates
  BLU's clock, then RED's:
  - named `zz_*_koth_timer`;
  - `SetShowInHud(true)`, but never chosen as the HUD timer;
  - `SetTime timer_length`, then `Pause`;
  - registered with `rounds:SetTeamClock`.

  `RoundActivate` (after capture) applies `PointLock()` to every point.
  `SetRed/BlueKothClockActive` goes to `rounds:ActivateTeamClock`.
  `SetRed/BlueTimer` and `AddRed/BlueTimer` reach the clocks' timer models.
  The master's win check calls `rounds:MayWinByPoints(winner)` before
  declaring.
- **Capture end order** (`CTriggerAreaCapture::EndCapture`), in this order:
  1. the area's `OnCap*` outputs and `OnEndCap`;
  2. respawn adjustments;
  3. `rounds:CapSounds(team, master:WouldNewOwnerWin(...), objective:ScorePerRound())`;
  4. `set:SetOwner(CAUSE_CAPTURE)`;
  5. the point's outputs, cap sound, model and notice;
  6. scoring (`HandleScoring`, with `mode.SCORE_CHIME_TO_ALL`);
  7. the master's win check.
- **Point scoring and announcements** keep sv_controlpoint's behaviour:
  contested lines, final-cap warning every 5 s, "defended" notice.
  `SetOwner` from an input sounds only when the caller is a player.
- **The HUD's `required`** is `team_numcap` of the capping team or, idle,
  of the team in the zone. `REASON_WAITING` applies when
  `0 < cappers < required` and `mp_capstyle 0`.

## 5. Bindings (entities: no rules)

Every binding stores its keyvalues. In `Initialize` it calls
`WETSAND.Feature(...)` and a `Bind*`. Its `AcceptInput` is an INPUTS table
keyed by lowercased input name, forwarding to the controller. Outputs are
fired by the controller on the entity (`TriggerOutput`).

| entity | feature | keyvalues | inputs | outputs fired by the controller |
|---|---|---|---|---|
| tf_gamerules (R) | rounds | `On*` stored | today's INPUTS; `SetRed/BlueKothClockActive` → `ActivateTeamClock`; `SetCTFCaptureBonusTime`, `HandleMapEvent`, `SetMapForcedTruceDuringBossFight`, `SetCustomUpgradesFile` accepted and ignored | OnStateEnter*, OnStateExitPreRound, OnWonByTeam1/2, Team1/2PlayersChanged |
| team_round_timer (R) | rounds | today's `INT_KEYS` | today's (`DoInput` kept for Lua callers) | the model's `output` events |
| game_round_win, tf_logic_competitive (R) | rounds | as today | as today | OnRoundWin; OnSpawnRoomDoorsShouldLock/Unlock |
| team_control_point (engine) (C) | capture | via `WETSAND.KeyValues` | SetOwner, SetLocked, SetUnlockTime, HideModel, ShowModel, RoundActivate (AcceptInput hook installed by the controller) | OnCapTeam1/2, OnCapReset, OnOwnerChangedToTeam1/2, OnRoundStartOwnedByTeam1/2, OnUnlocked (`WETSAND.FireOutput`) |
| team_control_point_master (C) | capture | as today | Enable, Disable, SetWinner, SetWinnerAndForceCaps, RoundSpawn, RoundActivate, SetCapLayout, SetCapLayoutCustomPosition* | OnWonByTeam1/2 |
| team_control_point_round (C) | capture | as today | Enable, Disable, RoundSpawn | OnStart, OnEnd, OnWonByTeam1/2 |
| trigger_capture_area (C) | capture | as today | as today | as today |
| tf_logic_koth (K) | koth | timer_length, unlock_point | RoundSpawn, RoundActivate, SetRed/BlueTimer, AddRed/BlueTimer | none (TF2 has none) |
| tf_logic_cp_timer (M) | capture | controlpoint, timer_length, team_number | RoundSpawn (re-find point) | OnCountdownStart, OnCountdownEnd |
| trigger_ignite (M) | none (a `wetsand_trigger_volume`) | burn_duration, damage_percent_per_second, ignite_particle_name, ignite_sound_name | Enable, Disable | none |
| tf_logic_on_holiday (M) | holiday | none | Fire | IsHalloween, IsSmissmas, IsTFBirthday, IsFullMoon, IsAprilFools, IsValentines, IsNothing (from `holiday:HolidayActive`) |
| filter_tf_condition (M, P2) | none | condition, Negated | as a filter | none |
| tf_logic_medieval (M) | none (a `wetsand_stub_point`) | none | none | none |

## 6. Views

All views draw through `SandcastleHUDPaint(w, h)` and read only networked
state. `wetsand_hud_timer_y` stays and positions the top row.

- **Rounds view.** Today's timer box and labels (PREPARE, SETUP, OVERTIME),
  hidden when `wetsand_round_hud_type == HUD_KOTH` (the KOTH panel replaces
  it); a "+m:ss" flash beside the timer for 2 s on
  `wetsand_timer_time_added`; the pre-round and respawn countdowns; the
  announcement line; the round panel, win, sudden death and game-over
  panels, and notices (from cl_rounds); the announcer (from cl_announcer).
- **Capture view.**
  - Point icons in `Capture.Layout` rows, centred under the timer. Each
    icon shows:
    - the owner colour, and the rank + 1 or the print name's initial;
    - a padlock bar while locked;
    - the unlock countdown seconds while `unlock_time` is in the future;
    - a progress bar in the capping team's colour;
    - `xN` or `N/required`, or BLOCKED;
    - small RED and BLU ticks for `*_can_cap`;
    - a dimmed icon when not `in_round`;
    - a `timer_end` countdown under it.
  - Hidden points are skipped.
  - While `wetsand_capture_point > 0`, a capture panel above the crosshair
    shows the localized `REASON_TOKEN` text, via the rounds text
    `Localize`.
  - The unlock announcer (`Announcer.RoundBegins5Seconds`..`1Seconds`, then
    `Announcer.AM_CapEnabledRandom`) runs for the first locked point with a
    pending unlock time, while the round is running.
  - Drawn for `HUD_CONTROL_POINTS`, `HUD_KOTH` and `HUD_PAYLOAD` (payload
    hides cart points).
- **KOTH view.**
  - BLU's clock left and RED's right, in team colours; the running one
    bright, the paused one dimmed.
  - The OVERTIME label while `wetsand_round_overtime`.
  - Each running clock speaks "Mission ends in 60/30/10/5..1"
    (`ArmClientWarnings`/`NextClientWarning`), re-armed when its paused
    state or length changes.
- **Payload view.** The cart bars (moved as is) and the race announcer
  sounds (cl_payload, moved).

## 7. Work packages

Each package works in its own worktree and edits only the files it owns.
It asks for other changes in its report.

| pkg | owns | depends on |
|---|---|---|
| **R rounds** | foundation/rounds.lua (rewrite); foundation/rounds/{timer,text,control_points}.lua (new); features/rounds/{sv,cl}.lua (new); entities/{tf_gamerules,team_round_timer,game_round_win,tf_logic_competitive}.lua; wetsand/{cl_hud,sh_core}.lua (edits); deletes wetsand/{sv_rounds,cl_rounds,cl_announcer}.lua; cl_init.lua; features/editors/sv.lua (timer lines only); tests/{rounds_game,rounds_timer,rounds_text,rounds_rules,rounds_modes}_test.lua, tests/fake_objective.lua | lands first, together with C |
| **C capture** | foundation/capture.lua (rewrite as PointSet); foundation/capture/{area,master}.lua (new; area = today's capture.lua); features/capture/{sv,cl}.lua (new); entities/{team_control_point_master,team_control_point_round,trigger_capture_area}.lua; deletes wetsand/sv_controlpoint.lua; call-site edits in wetsand/{sv_payload,sv_teams_spawn,sv_spectate}.lua, entities/{team_train_watcher,filter_activator_tfteam,headless_hatman}.lua; tests/{capture_area,capture_points,capture_master}_test.lua (capture_test.lua renamed to capture_area_test.lua; the capture-order and mini-round cases move here from rounds_rules_test) | R's interfaces (section 2.4); merges right after R |
| **K koth** | foundation/rounds/koth.lua; features/koth/{sv,cl}.lua; entities/tf_logic_koth.lua; tests/koth_test.lua | model and test: R's and C's models; controller and view: R+C merged |
| **P payload** | foundation/rounds/payload.lua; features/payload/{sv,cl}.lua; deletes wetsand/{sv_payload,cl_payload,cl_hud}.lua; entities/{team_train_watcher,tf_logic_multiple_escort}.lua; foundation/payload.lua (callers of its duplicated point rules → master); features/editors/sv.lua (cart lines only); tests/payload_mode_test.lua (updates payload_test only where functions move) | R+C merged |
| **M logic** | foundation/capture/point_timer.lua; entities/{tf_logic_cp_timer,trigger_ignite,tf_logic_on_holiday,filter_tf_condition,tf_logic_medieval}.lua; tests/{capture_point_timer,trigger_ignite}_test.lua (and a pure `foundation.hazards.ignite` part if the burn needs a rule beyond the trigger volume) | R+C merged |
| **T tools** (written with this plan, left uncommitted for the integrator) | .devtools/bin/{map_census,test_map_census}.py | none |

Merge order:
1. R, then C, back to back.
2. The integrator's payload check (section 9.3, pl_badwater and plr_hightower).
3. K, P and M, in any order.

K's model and test can be written during wave 1, against R's and C's model
interfaces, and merged once R and C are in.

### 7.1 Acceptance criteria (every package)

- `.devtools/bin/check_lua.sh` passes: every file compiles, and every test
  passes.
- `.devtools/bin/check_names.py` passes. No "TF2"/"tf2" appears in our
  identifiers. Every Global2 or NW2 key read is set somewhere.
- `luajit -bl <foundation file> | grep GGET` shows only the globals
  captured above `module(...)`.
- No bare meaningful integers, tests included: teams, states, reasons, HUD
  types, causes and orders use the named constants.
- One field per line in multi-field tables.
- No entity file requires anything at top level. A binding contains no
  rule: `grep -nE 'if .*(RED|BLUE|owner|locked|TeamMay)' entities/entities/<binding>.lua`
  finds only input parsing.
- Each test was written first and seen failing (say so in the report).
- Views read only networked state. No `ents.Find*` appears in any `cl.lua`.

### 7.2 Per-package model scenario tests

The tests run under LuaJIT with a fake clock and a scripted random source.

**R rounds**

- **`rounds_game_test`** (a `Round` with `fake_objective`, driven through
  whole rounds; each asserts the effect list in order):
  1. PREGAME holds without players. With players it goes to PREROUND,
     emitting `balance_teams`, `activate_timers`, `round_spawn`,
     `round_activate`, `new_round_outputs`, `respawn_all`, `doors_lock`,
     and `output OnStateEnterPreRound`. There is no `cleanup` on the fresh
     map. After 3 s it goes to RND_RUNNING with `doors_unlock`,
     `output OnStateExitPreRound`, `output OnStateEnterRoundRunning` and
     `hook WetsandRoundActive`.
  2. `SetWinningTeam(RED, DEFEND_UNTIL_TIME_LIMIT, full reset, switch)`
     gives `score RED 1`, `publish_win`, TEAM_WIN, `win_song` and
     `output OnWonByTeam1`. After the bonus time it goes to PREROUND with
     `cleanup`, `switch_teams` and `new_round_outputs`.
  3. A mini-round win (`forceMapReset=false`) gives no score and
     `previous_round_end`, then PREROUND with no `cleanup` and no
     `new_round_outputs`.
  4. `SetStalemate` with stalemate disabled gives a drawn round. Enabled:
     STALEMATE, `sudden_death`, `respawn_all`, `hide_timers` and
     `stalemate_timer 240`. One team dead gives `stalemate_winner` to the
     survivors. Everyone dead, or the stalemate timer out while
     `timerMayExpire`, gives a stalemate win. Leaving gives
     `restore_timers`.
  5. Win limit 2: the second win goes to GAME_OVER with `intermission
     "Reached Win Limit"`, then `changelevel` after chattime. Max rounds
     and the time limit (`CanChangeLevelForTimeLimit` with play-all-rounds)
     work the same way.
  6. `Halt` goes to BETWEEN_RNDS with `doors_unlock` and
     `output OnStateEnterBetweenRounds`; Think does nothing until
     `Unhalt` and `RestartRound`.
  7. `TimerMayExpire`: a hold with `capturing` at t makes it false until
     t+0.1, then true. An `other` hold is false only while held.
  8. Waves: `NextRespawn` for teams of 1 and 8, the admin override, the
     map value and the default, and `MayRespawn` in setup; `WaveDue`
     advances by the wave length.
  9. The mode's `CREATES_TIME_LIMIT_TIMER` false suppresses
     `time_limit_timer` with `timelimit` set.
- **`rounds_timer_test`** (the timer model):
  1. Setup 60 then normal 270: `OnSetupStart`; the setup marks 60/30/10/5..1
     one per think; `OnSetupFinished`, then `OnRoundStart`; `setup false`.
  2. At zero with `mayExpire` false and `showInHud`: `overtime true`, the
     clock holds, a nag at most once a second on a coin flip. Then
     `mayExpire` true: `OnFinished` once and `overtime false`.
  3. A clock not shown in the HUD holds without overtime events.
  4. `AddSeconds` clamps to `maxLength`, bumps the serial, and emits
     `time_added` only when `announces` and `isHud` and not `roundWon`.
  5. `RoundSpawn` with `resetTime` false carries normal time into the next
     mini-round, and with true restarts it.
  6. Pause and resume, disabled ignoring inputs, `SetShowInHud`.
  7. `ChooseActiveTimer`, `ArmClientWarnings` (the +2 s padding) and
     `NextClientWarning`, ported.
- **`rounds_modes_test`**:
  1. `SetMode` priority: cp, then payload, then koth gives koth; koth,
     then cp stays koth.
  2. `control_points.CapSounds`: a non-winning cap with score per round
     gives Success/Failure; no lines when it wins the game or with score
     per capture.
  3. Base mode defaults.
  4. `Mode:Extend` inheritance.
  5. A contract test: `fake_objective` implements `OBJECTIVE_METHODS`, and
     `NO_OBJECTIVE`'s defaults.
- **`rounds_text_test`**: moved as is, plus `TimeAdded(180) == "+3:00"`.

**C capture**

- **`capture_points_test`** (PointSet scenarios):
  1. **cp_granary**, built from its real keyvalues:
     - RED may cap the neutral mid, not BLU's 2nd.
     - After owning the mid, RED may cap BLU's 2nd, then BLU's last, never
       skipping.
     - With `caplinear` false, anything goes.
     - The mid shows `REASON_LINEAR` to BLU on RED's 2nd.
  2. **cp_dustbowl stage 1**, with the master's in-round set for round_1:
     - BLU may cap `cap_red_1` (self-previous), and `cap_red_2` only after
       `cap_red_1`.
     - Round 2's points are not in the round.
     - RED may cap nothing (`team_cancap` belongs to the area; here, the
       owner check).
  3. **cp_steel**: per-team previous points gate A→B→C→D; E needs itself.
     `SetOwner(CAUSE_INPUT)` from a relay is not `sounding`.
  4. **KOTH lock**: `SetLocked(true)`, then `SetUnlockTime(30, t)`:
     - `Tick` before `RND_RUNNING` never unlocks.
     - While running, it unlocks at t+30 with one `unlocked` event.
     - `SetLocked(false)` clears the unlock time.
     - `RoundActivate` emits `round_start_owned` and `unlocked` for a
       never-locked point.
  5. `TeamOwnsAll` by groups; `CannotCapReason` for each `REASON_*`, in
     TF2's order; `Capture.Layout("4, 0 1 2 3", 5)` and `("", 3)`.
- **`capture_master_test`**:
  - The mini-round cases moved from `rounds_rules_test` (`ChooseRound`,
    history, `RoundPlayable`, `RoundsRemaining`, `Stage`).
  - **cp_gorge**: restrict RED; BLU owning both wins; RED owning all
    (default) never wins.
  - `SetWinnerArgs(0)` is a stalemate with `forceMapReset` only when
    nothing is playable.
  - `BaseControlPoint` with mini-rounds uses in-round points (G8, which
    fails today).
- **`capture_area_test`**: today's `capture_test`, plus
  `PointSounds` for each event and `SF_NO_CAP_SOUNDS`.
- **Seam checks** (read as text in a test):
  - `trigger_capture_area.lua`, `team_control_point_master.lua` and
    `team_control_point_round.lua` contain no `foundation.` require.
  - The capture controller defines every method in section 2.4's capture
    list: `function Controller:<Name>(`.

**K koth: `koth_test`** (Round, Timer, PointSet, Master and the koth mode
together, on a fake clock):

1. `Koth.New{}` defaults to 180/30. `Clocks()` gives BLU then RED, named
   `zz_*_koth_timer`. `PointLock()` gives locked with 30; with
   `unlockPoint 0` it gives unlocked and no time.
2. RED caps at t=40, so `ClockActive(RED)` resumes RED's clock and pauses
   BLU's. At t=220 RED's clock reads 0. With RED owning the point:
   `MayWinByPoints(RED)` is true only when `timerMayExpire`.
3. **Overtime.** RED's clock reaches 0 while BLU is capping: the clock
   holds, `overtime true`, no win. BLU leaves: after the 0.1 s buffer RED
   wins.
4. **Overtime lost.** BLU completes the cap: BLU's clock resumes, RED's
   pauses at 0, and BLU's think (time > 0) emits `overtime false`.
5. `koth.CapSounds` gives each team `Hud.PointCaptured` and
   Success/Failure, even when the cap would win. `ANNOUNCES_TIME_ADDED`
   and `CREATES_TIME_LIMIT_TIMER` are false. The mode's `HUD` is
   `HUD_KOTH`.

**P payload: `payload_mode_test`**

- `RoundWinLines` on a race matches `Race.OutcomeLines`; none without a
  race.
- `SCORE_CHIME_TO_ALL`; `PRIORITY` over control points.
- `payload_test` and `payload_race_test` pass unchanged, apart from moved
  calls.

**M logic**

- **`capture_point_timer_test`** (degrootkeep):
  1. BLU may cap point 3 at t, so the timer starts once, with
     `endTime = t+60`, and `MayExpire` is false.
  2. At t+60 with BLU capping, it waits. At the first think with nobody
     capping, it emits `end` once and resets.
  3. When the team may no longer cap, it goes idle without `end`.
  4. A round won invalidates it. The 15/10/5 flags produce no events.
- **`trigger_ignite_test`**, only if a rule part is needed: the burn
  cadence and damage percent against `CTriggerIgnite::BurnEntities`.

### 7.3 Loading checks (integrator, `wetsand_memory` and `package.loaded`)

| map | features loaded (besides any Halloween ones) |
|---|---|
| koth_viaduct | rounds, capture, koth (no payload; `foundation.payload` not in `package.loaded`) |
| cp_granary | rounds, capture (no koth, no payload) |
| pl_badwater | rounds, capture, payload (no koth; `foundation.rounds.koth` not loaded) |
| gm_construct | none of the four |

## 8. Out of scope, with reasons

- **Game modes the census found once:** player destruction, CTF on
  cp_carrier, MvM upgrade stations, minigames and wheel of doom.
- **`game_intro_viewpoint`:** the join-time map tour. Sandcastle's team
  menu replaces it.
- **VScript** (`logic_script`, `vscripts` keyvalues on 13 maps):
  - GMod has no Squirrel.
  - cp_sulfur's `koth_setup.nut` and `timer_fix.nut` will not run, so
    cp_sulfur may play oddly.
  - koth_krampus and koth_slime lose their scripted extras.
- **Medieval weapon restrictions** and **Huntsman arrow ignition:** there
  are no TF2 weapons.
- **Tournament stopwatch**, `SetCapLayoutCustomPosition`, and the
  per-point `random_owner_on_restart` (used by no map).
- **Achievements, holiday soul packs, bonus ducks** (econ).

## 9. In-game checklist (integrator, after the merges named)

Use a local server with bots (`bot`, then `wetsand` team commands) and
`mp_stalemate_enable 1` where noted.

### 9.1 After R+C

**cp_dustbowl** (no `tf_gamerules` in the BSP):
- A `tf_gamerules` exists after load.
- The HUD shows SETUP 1:00. The gates open on `OnSetupFinished`.
- The goal strings show (sent to the name `tf_gamerules`).
- BLU caps 1-A: +4:30 flashes by the timer, and the time-awarded lines
  play to each side.
- 1-B locked-by-order shows `#Team_Capture_Linear` on the capture panel.
- Stage 1 won: "BLU TEAM SEIZES AREA", no map reset. Stage 2 has setup
  again. The icons dim the other stages' points.
- Let the timer run out while BLU is on a point: OVERTIME, the
  "Overtime!" line, and no RED win until the cap breaks (0.1 s later).
- RED's full-round win swaps teams.

**cp_granary:**
- 5 icons in one row; the mid is neutral.
- The capture panel on BLU's last point from the mid says it cannot be
  captured yet.
- Capture sounds: the hologram start, loop, and stop, and the interrupted
  loop when blocked.
- A non-winning cap plays "Success" to the cappers and "Failure" to the
  others.
- The timer runs out: sudden death with `mp_stalemate_enable 1`, a
  stalemate without it.

**cp_gorge and cp_gravelpit** (no `tf_gamerules`):
- Setup, then `AddTime`/`AddTeamTime`.
- Gravelpit's icons in two rows ("2, 0 1").
- C only after A (BLU). The overtime hold on the last point.

**cp_steel:**
- The layout "4, 0 1 2 3".
- `OnMultiNewRound` ran: BLU's wave time is 6 s shorter (check
  `rounds:TeamRespawnWaveTime(3)`).
- The early-finish relay's `SetOwner 3` chain makes no capture sounds.

**cp_badlands:** the proxy is named `gamerules`. `SetStalemateOnTimelimit`
is honoured with `mp_timelimit` set.

**Payload regression:**
- On pl_badwater and plr_hightower, carts move, roll back and alarm.
- The race HUD and lines work, as does the final point.
- Payload overtime holds on the pushed cart.
- `wetsand_memory` shows no koth.

**Spawns and filters:** respawn rooms and team filters follow point owners
on dustbowl stage 2 (sv_teams_spawn, filter_activator_tfteam).

### 9.2 After K

**koth_harvest_final or koth_viaduct:**
- The point shows a lock and "unlocks in 30"; 5..1 is spoken, then the cap
  line.
- The first cap starts the capper's clock. Both clocks are drawn and the
  running one is highlighted.
- The clock speaks "Mission ends in 60 seconds"…
- RED's clock at 0 while BLU caps gives overtime; the break gives RED's
  win. The win panel shows "RED TEAM WINS!".
- On viaduct, the spawn doors lock at pre-round (`tf_logic_competitive`).

**koth_lakeside_final:** the gamerules proxy is named `koth_gamerules`; the
unlock is 35 s; the point's 8 s cap.

**cp_sulfur:** `tf_logic_koth` with a map timer: the KOTH clocks show, the
map timer is not the HUD timer when KOTH is active, and the VScript log
appears once.

**koth_sawmill** (no `tf_gamerules`): the rounds run.

**Name targets:** koth_slasher, koth_probed and koth_synthetic_event send
`AddOutput` to `zz_*_koth_timer` from `OnMultiNewRound`: on koth_slasher
the added output fires at its mark.

### 9.3 After M and P

- **cp_degrootkeep:** BLU able to cap C starts the 60 s countdown under C
  and sets BLU waves to 0. At expiry, with nobody capping, A and B go back
  to RED. The map timer's `OnFinished` goes to `SetWinner 2`, and RED wins
  unless BLU is capping.
- **cp_gravelpit_snowy or cp_lavapit_final:** `trigger_ignite` burns.
- **cp_fortezza:** `tf_logic_on_holiday Fire` gives `IsNothing` (no
  holiday forced).
- **`game_text_tf`:** `ents.Create("game_text_tf"):IsValid()` is true in
  GMod; the `display` on cp_granary shows text.
- **After P:** none of `wetsand/{sv_payload,cl_payload,cl_hud}.lua`
  exists, and payload plays as in 9.1.

## 10. Judgment calls to revisit

- **One CP strategy for symmetric and A/D** (decision 3). The operator's
  example listed them separately; TF2 does not branch.
- **The `Round` model ports the whole `tf_gamerules` state machine now.**
  This is the largest part of R. The alternative was to wrap the entity and
  keep the rules in it, which the lua skill forbids.
- **R and C merge as a pair.** Each deletes a legacy file the other's
  entities call. Splitting them further would need a shim file with two
  owners.
- **Creating the proxy on maps without one** makes every map with an
  objective entity a TF2 map for `WETSAND.Active()`.
- **`OnMultiNewMap` is suppressed** by overriding the keyvalue during
  cleanup. `OnMultiNewRound` fires one tick after cleanup, not in the
  `logic_auto`'s own think, so its order against `OnMapSpawn` may differ
  from TF2's. Outputs with delays are unaffected.
- **KOTH clocks are real entities**, not model-only timers, because maps
  target them by name.
- **Point icons are drawn shapes**, as today, not TF2's `obj_icons`
  materials (their presence in the mount was not verified).
- **Networking uses Global2 per point**, as payload does, published at
  10 Hz, rather than a net message on change.
- **`trigger_ignite_arrows`, `game_intro_viewpoint` and `func_achievement`
  are not stubbed.** The engine drops unknown classes and no map sends
  them inputs.
- **`filter_tf_condition` is P2 inside M.** Drop it if
  `foundation.players.COND` lacks the conditions koth_undergrove_event
  uses.
- **`team_control_point` `Enable`/`Disable`** stay unhandled, as in TF2.
