# The AI war on NextBot's components: plan

Status: approved 2026-11-20 (the unsafe binding pattern included). Slices 1 and 2 done.

## Why

At 16v16 the AI war takes 458 ms of every second of the server thread
(`aiwar_tick_probe`, pl_upward, 31 bot players, 2026-11-20); the server ran
56 ticks a second instead of 66.7. The decisions are the small part: the
soldiers' trees (`TreeJob`) are 63 ms/s. The rest is a bot player's *body*,
run in Lua: its keys every tick, its route walked, its footing traced, who
its enemies are.

The idea: express what the war and the tactics engine ask of a soldier in
the vocabulary of Source's NextBot components, `IVision` (with
`CKnownEntity`), `ILocomotion` (with `PathFollower`) and `IBody`, as the SDK
names them (`src/game/server/NextBot/`), and answer those questions in the
components, natively, where TF2's bots answer them. Lua keeps what is the
war's own: orders, tactics, kits, call-outs. The soldier port
(`nextsoldier.behavior.PORT`) stays the seam; only what answers it moves.

Example, as asked: an enemy's memory is `IVision::GetPrimaryKnownThreat()`
and `CKnownEntity::GetLastKnownPosition()`, not a table the war keeps
(today `BotSoldier.lastSeen`, `sv_bot_soldier.lua`).

## What is already there

- `CLuaNextBotVision` (Rust, `nextbot/vision.rs`): looks, remembers
  (`known.rs` keeps `last_known`), ranks and tells, for NextBots and, since
  `7d400de`, for bot players. It is not yet a bot player's `IVision`: its
  `GetPrimaryKnownThreat`/`GetKnown` are not among the slots an actor
  answers (`component.rs`'s `Vision`), and Lua reads it by its own handle.
- `CLuaNextBotBody` (Rust, `nextbot/body.rs`): a NextBot's hull, posture,
  animation and attention; a bot player's head is `body/look.rs`'s.
- `component.rs`: `Locomotion`, `Body` and `Vision` as traits, a method per
  SDK slot an actor may answer (`Approach`, `Jump`, `Run`/`Walk`,
  `FaceTowards`, `IsStuck`, `AimHeadTowards`, `SetDesiredPosture`, ...).
  No `PlayerLocomotion` implements `Locomotion` yet.
- `player_input.rs`: a bot player's `INextBotPlayerInput`, pressed natively
  (`engine.PressFireButton`, settled live).
- `engine.ComputePath`: the engine's own search for NextBots and bot
  players, priced by our `IPathCost`.
- NextSoldier's own plan for the body (`addons/nextsoldier/docs/gmod-player-bot.md`):
  a native `PlayerLocomotion` acting through `INextBotPlayerInput`, so that
  GMod's own `PathFollower` drives a bot player as it drives an NPC
  (`PathFollower::Update` speaks only to `ILocomotion`); an `IBody` swap onto
  `look.rs`; then `player_body.lua`'s key path retired. Step 1 is done, the
  `ILocomotion` layout read (`fc1fafc`); the `PlayerLocomotion` is not built.

## The mapping

Measured costs are the probe's (inclusive, wrapped; `.devtools/artifacts/aiwar_probe_16v16_vision_methods.txt`).

### The war's own hot paths

| Today (Lua) | ms/s | In NextBot's terms | Where it would run |
|---|---|---|---|
| `Drive` → `player_body:Command`: move keys toward `steer`, walk, crouch, jump | 199 (all of Drive) | `ILocomotion::Approach (goal)`, `Run`/`Walk`/`Stop`, `Jump`, `IBody::SetDesiredPosture (CROUCH)` | `PlayerLocomotion` (Rust), pressing `INextBotPlayerInput` |
| `Drive`: eye angles toward the aim, the hand's pan (marksmanship `pan`) | | `IBody::AimHeadTowards (subject, priority, duration)`, `GetMaxHeadAngularVelocity`, `GetHeadAimTrackingInterval`, `GetHeadAimSubjectLeadTime`, `IsHeadAimingOnTarget` | `IBody` swap onto `look.rs` |
| `Drive`: fire, reload, use a door | | `INextBotPlayerInput::PressFireButton`, `PressReloadButton`, `PressUseButton` | native (exists); the *decision* stays Lua (orders' `mayFire`) |
| `Look` → `Steer` → `route_walk`, `SteerOn`, `Avoid`, `FeelAhead` | 115 (Steer 39, FeelAhead 7, Avoid 5) | `PathFollower::Update (bot)`: waypoints, `Avoid` (its feelers), `Climbing`, `JumpOverGaps`, `CheckProgress` | the engine's `PathFollower` over `PlayerLocomotion` |
| `StandOnRoute`, `Stands`, `Reaches`, `CanWalkTo`, `WalkClear` | 84 + 22 + 11 | `ILocomotion::IsPotentiallyTraversable (from, to)`, `HasPotentialGap`, `IsGap`, `GetStepHeight`, `GetDeathDropHeight` | `ILocomotion`'s own (the SDK's base implements them with hull traces) or ours in Rust |
| `FightsAgainst` + `Fighters` (my vision opinion) | 33 | `INextBot::IsEnemy`, `IVision::IsIgnored`: by team number, and what the mode marks as fought (`ent.Combatant`) | Rust, in the vision's opinion: no Lua call per look |
| `lastSeen`, `Saw`, `EnemyPosition` out of sight | small | `CKnownEntity::GetLastKnownPosition`, `WasEverVisible`, `GetTimeSinceLastSeen` | `CLuaNextBotVision` (`known.rs` has them) |
| `TreeJob` | 63 | the engine's `Behavior` (`main_nextsoldier`) | stays: it is the war's decisions |

### The soldier port, as wartactics and the orders use it

Counts are call sites in `addons/wartactics/`, NextSoldier's `behavior/` and
`squad/`, and the war's orders (`ns_behaviors.lua`).

| Port methods (call sites) | In NextBot's terms | Component |
|---|---|---|
| `HasEnemy` (14), `Enemy` (4), `EnemyPosition` (8) | `GetPrimaryKnownThreat (onlyVisible)`, its `GetEntity`, `GetLastKnownPosition` | Vision |
| `EnemyHealth` (2) | the known entity's health | Vision + entity |
| `LookAt` (2), `Watch` (1) | `IBody::AimHeadTowards (pos, priority, duration)` | Body |
| `Position` (36), `RangeTo` (27) | `ILocomotion::GetFeet`, `INextBot::GetRangeTo` | Locomotion / INextBot |
| `MoveTo` (25), `Release` (17), `Hold` (8), `Stand` (4), `Repath`, `RequestRoute`, `RouteResult`, `RouteStale`, `PlansRoutes`, `Unfollow` | `engine.ComputePath` + `PathFollower::Update`; `ILocomotion::Stop`; `Path::GetAge`/`IsValid` | Locomotion + Path |
| `CanWalkTo` (3), `Detour` (1), `PassBlocker` (1), `DoorToOpen` (2) | `IsPotentiallyTraversable`, `PathFollower::Avoid`, `IsEntityTraversable`, `ShouldCollideWith` | Locomotion |
| `Hop` (1) | `ILocomotion::Jump`, `JumpAcrossGap`, `ClimbUpToLedge` | Locomotion |
| `Pose` (4), `Unpose` (5), `Sit`, `IsSeated` (2), `Gesture` (4) | `IBody::SetDesiredPosture`, `GetActualPosture`, `StartActivity` | Body |
| `HurtSince` (2) | `OnInjured` event / the vision's `Hurt` | Vision / events |
| `Health`, `MaxHealth`, `IsAlive`, `IsDisarmed`, `Burning`, `Now` | the entity's and the game's | stays |
| `Mark`, `Announce`, `CallMedic`, `UseGadget`, `Heal`, `HealthKits`, `CoverSpot`, `PatrolSpot`, `WanderSpot`, `FollowCart` | the war's own | stays Lua |

So about 30 of the 45 methods are component questions; the rest are the
war's.

## Slices, by payoff

Each slice: tests first (Rust for what is native, LuaJIT for the port's
answers), then the 16v16 bench (`aiwar_bench.py`, its scenario, the probe's
hooks-only mode) against the 458 ms/s baseline, and a played round on
pl_upward with no Lua errors.

1. **Done 2026-11-20 (NextSoldier `5728e6d`, Sandcastle `f89f4e7`). The war's opinion in Rust.** Hostility by team number and the mode's
   marks, answered in the vision without a Lua call (an opinion the host
   chooses, e.g. `opinion = "teams"`); `BotOpinion` keeps only `MoreDangerous`
   (the orders' pick). Small; removes `FightsAgainst`'s 18 ms/s.
2. **Done, with 1. Enemy memory in the vision.** `vision:LastKnown (ent)` (or the SDK's
   `GetKnown`/`GetLastKnownPosition` through `actor.vision`), and the port's
   `Enemy`/`HasEnemy`/`EnemyPosition` answered from it; `lastSeen` goes. Small.
   Needs a binding function: the unsafe question below.
3. **`PlayerLocomotion` in Rust** (NextSoldier's plan, step 2): `Approach`,
   `FaceTowards`, `Jump`, `Run`/`Walk`/`Stop`, `IsStuck`, `GetGroundSpeed`
   through `INextBotPlayerInput`; `actor.locomotion`. Large; the base for 4.
4. **`PathFollower` drives the bot players**: `MoveTo`, `Release`, `Hold`,
   `Repath` on `engine.ComputePath` and `PathFollower::Update`; `Steer`,
   `route_walk`, `StandOnRoute`, `Avoid`, `FeelAhead` and `Drive`'s movement
   go. The biggest saving (most of `Drive`, `Look`, `StandOnRoute`: about
   300 ms/s).
5. **The head on `IBody`**: the aim and the hand's pan as `AimHeadTowards`
   with the marksmanship as the body's angular velocity, tracking interval
   and lead time; `player_body.lua`'s key path retired, `StartCommand` kept
   as the escape hatch.

### Key presses as standing orders (slices 3 and 5, as built)

Asked 2026-11-20: key presses as action code on think intervals, not per tick.
Lua decides at a look's interval (0.2 s); native code, in each soldier's
`Upkeep` (`main_nextsoldier.rs`, where `look.rs` already turns the head every
tick), turns the standing orders into the tick's buttons. This *is* the SDK's
`PlayerLocomotion::Approach` and `PlayerBody::AimHeadTowards`, which run every
update because `SetButtonScale` holds for 0.01 s (GMod's slot 24).

GMod's `INextBotPlayerInput` (win64 `server.dll`, vtable at the player's
`+0x3348`, 25 slots; the SDK's pairs without `SpecialFire`), read 2026-11-20:

| Slots | Button | Bit | Timer |
|---|---|---|---|
| 0/1 | Fire | `IN_ATTACK` 0x1 | +0x10 |
| 2/3 | AltFire | jumps to 4/5 | |
| 4/5 | Melee | `IN_ATTACK2` 0x800 | +0x18 |
| 6/7 | Use | `IN_USE` 0x20 | +0x20 |
| 8/9 | Reload | `IN_RELOAD` 0x2000 | +0x28 |
| 10/11 | Forward | `IN_FORWARD` 0x8 | +0x30 |
| 12/13 | Backward | `IN_BACK` 0x10 | +0x38 |
| 14/15 | Left | `IN_MOVELEFT` 0x200 | +0x40 |
| 16/17 | Right | `IN_MOVERIGHT` 0x400 | +0x48 |
| 18/19 | Jump | `IN_JUMP` 0x2 | +0x50 |
| 20/21 | Crouch | `IN_DUCK` 0x4 | +0x58 |
| 22/23 | Walk | `IN_SPEED` 0x20000 | +0x60 |
| 24 | `SetButtonScale (forward, right)` | +0x74, +0x78 | holds 0.01 s |

- **A. Done 2026-11-20 (NextSoldier `141a9de`). Every button bound natively**: `player_input.rs` holds each slot to its
  bit (or its jump, or the scale's fields) at bind; `engine.Press<X>Button`,
  `Release<X>Button`, `SetButtonScale`.
- **B. Done (NextSoldier `d6738e1`). `player_body.Command` in Rust** (`body/drive.rs`, pure): the hand's
  pan (marksmanship as it is), turning at `TURN_RATE`, stuck and wedged,
  jump and crouch-jump, firing on target only and a semi-automatic's taps,
  reload, chase and avoid, hurdles, lintels, doors. Its 22 LuaJIT tests
  (`nextsoldier_player_body_test.lua`) are its contract, carried into Rust.
- **C. Done (NextSoldier `1bfe755`). Drive in `Upkeep`**: a soldier's standing orders run each tick beside
  its head; position, velocity and ground read natively (as `reach.rs` reads
  fields, from GMod's own Lua C functions), the aim point from its
  `CLuaNextBotVision`'s estimate.
  What made it work, read from the binary: `PhysicsSimulate` moves a bot player at its
  `ILocomotion` slot 82 (`GetRunSpeed`) times the button scale, and the base answers 0, so a
  bot player never moved by its own keys (a native `PlayerLocomotion` answers it with the
  gait's speed: a walk is a slower run); it presses `IN_DUCK` whenever `IBody` slot 68
  (`IsActualPosture(CROUCH)`) answers true, which the base always does (a native posture
  answers it). Live: a bot sent 600 units ran straight there at 200 u/s, upright, the Lua key
  path off for it.
- **D. Done (Sandcastle `63645b1`). The war on it**: its look (0.2 s) sends the standing orders
  (`engine.Drive (ply, orders)`: target, gait, crouch and jump areas, hop,
  hurdle and lintel, door, look and its priority, enemy, pan, ranges, fire,
  weapon); `StartCommand/ws_aiwar_bots` and `player_body.lua`'s key path go.
  The 200 to 250 ms/s of `Drive` at 16v16 is what it removes.

### What the key presses as standing orders measured

pl_upward, 16v16 of bot players, a minute of combat, the probe's hooks alone
(`.devtools/artifacts/aiwar_probe_16v16_drive_*`): `StartCommand/ws_aiwar_bots`
33 ms/s from 209 (18 µs a call from 135); the looks' orders (`SendOrders`) 26
ms/s, 238 µs each, of which `engine.Drive` 14 µs and the rest the weapon's
ranges and state; the war 365 ± 8 ms/s from 458 ± 7; 64 ticks a second from 56.
The bots ran at their class's speed, upright, and fought (1,080 shots, 22 kills).
Next: the look's own cost (`Think/ws_aiwar_bots`, its route and footing work),
which `PathFollower` on the native locomotion would take.

### Where a look's time goes, and weapons picked by sightlines

pl_upward, 27 bot players, 2026-11-20. Measured by leaving each part of a look
out for 8 s and reading the calendar's own measure of its looks
(`.devtools/bin/aiwar_look_probe.lua`'s `Ablate`; timing between lines charges
a part with whatever else ran in it): a look about 1.35 ms, of which steering
about 500 µs, `SendOrders` 400, the weapon pick 280, the vision 250, the feel
ahead 160. A soldier's tree (`.devtools/bin/aiwar_tree_probe.lua`) about 730
µs an update, `Objective:Update` 380 of it and the two monitors 110 to 150
each. With the collector stopped the war fell only 6 %: the cost is calls
into GMod (a first call about 2 µs, a repeat 0.25; every `ply:Method` through
GMod's Lua `__index`), not garbage.

The pick ran at every look over all ten weapons a bot carries. Now
(`sv_bots.lua`'s `Arm`) it runs when the distance it fights or readies for
crosses into another band of what it carries (`Arms.Thresholds`, `Arms.Band`:
within a band, `Pick` chooses the same whatever the distance or the gun in
hand), its enemy changes, or the gun in hand is spent. With no enemy, the
distance is its place's sightline reach (`features.aiwar.sightlines`: 16 rays
at eye height against what blocks sight, the distance three quarters of them
go within; measured the first time a bot stands in an area, about 900 µs, and
kept), not a fixed 1000: the bots held a crossbow, pistols, shotguns and SMGs
by place where all held the SMG. A look re-picks on about one in five; head
to head in the same ticks, `Arm` 40 µs a look against 209 for the old pick.
The PVS was the other way to read a place's openness (the binary binds
`GetPVSForCluster`), but it sees cluster to cluster, round corners and
through closed doors; the rays read the walls.

### What slices 1 and 2 measured

`hostility = "teams"` (`world::by_teams`, TF2's `CTFBot::IsEnemy`; each body's
team in the world's snapshot, from the host's `TeamOf`) and
`vision:GetEnemyLastKnownPos`. On pl_upward, a minute of combat: 383
contacts, every one across teams; `Look` 83 ms/s from 115, `FightsAgainst`
gone; the war 393 ± 15 ms/s from 458 ± 7, with 28 bots against 31, so not
like for like (`.devtools/artifacts/aiwar_probe_16v16_slice12_combat_*`). The
worst ticks are `StandOnRoute`'s and `PlanRoute`'s (about 300 ms), and one
tick of 2.8 s outside the war's share, not yet explained.

## Questions for the operator (answered 2026-11-20: the pattern approved, the re-expression fine, slices 1 and 2 first)

- **Unsafe bindings.** Slices 2 to 5 add binding functions (`unsafe extern
  "C-unwind"`, as every binding is) and, for 3 and 5, vtable swaps on a bot
  player's `ILocomotion` and `IBody`, as the intention's swap already does.
  NextSoldier's CLAUDE.md asks before unsafe code: is this pattern approved
  for these slices?
- **Marksmanship as the body's terms.** Today's `pan` (frequency, damping,
  pursuit) and `track` gains would become `AimHeadTowards`' tuning: the
  difficulty levels would be re-expressed, and their tests with them.
- **Order.** 1 and 2 are small and independent; 3 to 5 are the large win
  and NextSoldier's own plan. Start with 1 and 2, or go straight to 3?
