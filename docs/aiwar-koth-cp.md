# AI War on King of the Hill and Control Point maps, and post-round carnage

Operator request: "work on the ai behavior and create new tactics and orders
for koth, cp, and seek and destroy for post round carnage against the losing
team."

Today the AI War refuses any map without a payload cart
(`features/aiwar/sv.lua` `Controller:Start`), and every order is built around
a cart. This plan does four things:

- makes the war's scenario a Strategy, chosen from the Round's mode;
- adds a control point scenario that covers both symmetric CP and
  attack/defend, and a KOTH scenario that extends it;
- adds new jobs and tactics for fighting over points;
- adds a post-round seek and destroy, in which the winners hunt the losers.

Payload keeps behaving exactly as it does today.

`sdk/` means `~/Repositories/source-sdk-2013/src/game/`. `G/` means
`addon/gamemodes/sandcastle/gamemode/`. Everything in `docs/aiwar-command.md`,
`docs/pass4-koth-cp.md` §0 and §2, and the `lua` skill still holds:

- models are pure `module(...)` files, tested by scenario under LuaJIT;
- behaviour varies by Strategy, never by map name;
- features load lazily;
- entities are thin bindings;
- every constant has a name.

Baseline on 9e75e34: `run_lua_tests.sh` passes 1048 tests with 0 failures,
`check_lua.sh` compiles 309 files, and `check_names.py` reports ok.

## 0. Decisions the operator should know

1. **The scenario comes from the Round's mode, never from the map.** The
   aiwar controller reads `WETSAND.Feature("rounds"):Mode().NAME`, but only
   when the `rounds` feature is already loaded. It never loads a feature just
   to check. It then picks the variant with `Scenario.For(name)`:

   | Mode | Variant |
   |---|---|
   | `"payload"` | `foundation.aiwar.scenario.payload` |
   | `"control_points"` | `foundation.aiwar.scenario.control_points` |
   | `"koth"` | `foundation.aiwar.scenario.koth` |

   Any other mode, or no rounds at all, refuses the start with the message
   "this map has no objective the AI war can fight over (payload, control
   points or King of the Hill)". This replaces the "no payload cart" refusal.
   The map's own entities already chose the mode (pass 4 decision 2), so
   `cp_dustbowl` and `koth_sawmill` work: rounds creates their
   `tf_gamerules`.
2. **One CP scenario covers symmetric and attack/defend maps**, as in TF2
   (`TF_GAMETYPE_CP`, pass 4 decision 3). Each team's posture comes from the
   capture state:
   - points it may capture now only: attack only;
   - its own points the enemy may capture now only: defend only;
   - both: a split, like payload's defense share on a race.

   A/D is simply the case where one side only attacks and the other only
   defends. KOTH extends CP, as `Koth.Mode` extends `ControlPoints.Mode`, and
   overrides two things: the hill is always a target (TF2's special case),
   and the stance reads the team clocks.
3. **This is the first slice of the Commander.** `docs/aiwar-command.md`
   phases 1 to 3 are built (queries, the monitor tree, squads). The
   Commander (phase 5) is not. The new `Scenario:Command(war, field, now)`
   runs once per controller think and sets each team's stance. It damps
   changes by `ALLOCATION_HOLD` (3 s), except for critical signals (§2.2 of
   that doc). For payload it calls today's `War:Assign`, so payload
   allocation does not change.
4. **Knowledge stays earned** (aiwar-command §0.6).
   - Capture state comes from what the capture HUD shows, through a new
     public query `capture:HudPoints()`.
   - Clocks come from the round and KOTH timers, which the HUD shows.
   - Enemies are known only from soldiers' own sightings. The hunt's shared
     board is a report channel: a hunter adds what it sees.
5. **New jobs `capture`, `assault` and `hold`.** They join the existing
   `defend`, `raid`, `support` and `medic`, which get point-based goals. The
   jobs of a scenario, with their goals, form a **doctrine**:
   - payload's doctrine is today's `ROLES` table, unchanged;
   - the point doctrine lives in the CP scenario part.

   `orders.lua` reads the doctrine from `field.doctrine`, so no job reads
   `field.carts` unless it is a payload job.
6. **Post-round carnage is a phase.**
   - `STATE.TEAM_WIN` with a winner becomes `PHASES.humiliation`, which has
     orders but no reinforcements.
   - Each winner's `TacticalMonitor` suspends for `SeekAndDestroy`. This
     copies TF2's `CTFBotTacticalMonitor::Update` "Get the losers!",
     `sdk/server/tf/bot/behavior/tf_bot_tactical_monitor.cpp:167-190`.
   - The losers' `Humiliated` runs from what it sees, and otherwise hides at
     its own spawn. TF2's losers do the same: "run and hide", with
     `CTFBotRetreatToCover`.
   - It all ends at the next round. `RespawnAll` rebuilds every stack, and
     `SeekAndDestroy` ends as soon as the phase changes.
   - A stalemate has no winner, so nobody hunts. That is today's behaviour.
7. **Sandbox mode is unchanged.** `Start` still asks for Gameplay mode with
   `Gamemode.SOURCE_AI_WAR`. On CP and KOTH maps that starts the countdown,
   then `Begin` restarts the rounds, as on payload.
8. **The changes are additive.** AI War was built by another session and may
   still move on origin/main.
   - The new files are `scenario.lua`, `scenario/*.lua` and `hunt.lua`.
   - `orders.lua`, `aiwar.lua` and `features/aiwar/sv.lua` get new functions
     and a handful of edits, each listed in §4.
   - Outside aiwar, one file changes: `features/capture/sv.lua` gains two
     read-only queries.
   - **Nobody stages `features/gamemode/sv.lua`**, which holds the
     operator's uncommitted edit.
   - Each package starts with `git fetch && git merge origin/main`.
9. **No new console variables.** Carnage is always on, as in TF2.

## 1. TF2 prior art adopted

| TF2 (sdk/server/tf/bot/…) | Adopted as |
|---|---|
| `behavior/tf_bot_scenario_monitor.cpp` `DesiredScenarioAndClassAction`: the game type picks the action (`TF_GAMETYPE_ESCORT` → payload; `TF_GAMETYPE_CP` → capture if a point is capturable, else defend) | `Scenario.For(mode NAME)`; the CP posture from attack and defend sets |
| `tf_gamerules.cpp` `CollectCapturePoints` / `CollectDefendPoints` (shared/tf, lines 17839 and 17883): in-round points; not owned and capturable; owned and capturable by the enemy; the KOTH single point always a capture target | `Objectives` (§2.5): `attack`, `defend`, the KOTH override |
| `tf_bot.cpp` `SelectPointToCapture`: stay on the point being captured, then the one a friend is capturing, then the nearest | `target` choice (§2.5) |
| `tf_bot.cpp` `GetTimeLeftToCapture`: in KOTH the **enemy's** clock, otherwise the round timer | `timeLeft` in `Objectives`; the KOTH override |
| `capture_point/tf_bot_capture_point.cpp`: `isPushingToCapture` (a friend capping, overtime, time < `tf_bot_offense_must_push_time` 120, near the point); moves to a random spot on the point every 0.5–1 s while capping; `ShouldRetreat` NO and `ShouldHurry` YES when time is short | `capture` job: `Zone` (shuffle in the area), `Urgent`, `MUST_PUSH_TIME`, `NEAR_POINT` (750, `tf_bot_near_point_travel_distance`) |
| `capture_point/tf_bot_defend_point.cpp`: defend areas that see the point, within `tf_bot_max_point_defend_range` 1250, not more than 250 past the point (except in KOTH), not 220 below it; `IsPointThreatened` = contested within 5 s, or just lost | `Posts.ScoreGuard`; `threatened`; `CONTESTED_MEMORY` |
| `capture_point/tf_bot_defend_point_block_capture.cpp`: get on the point until it is safe; safe when our cap share is ≥ `tf_bot_defend_owned_point_percent` 0.5 | `hold` job; `CRITICAL_PROGRESS` 0.5 |
| `tf_bot.cpp:1682` `m_justLostPointTimer` 10–20 s: after losing a point, stand on the next one against a rush | `JUST_LOST_TIME` 15; the A/D fall back |
| `tf_bot_seek_and_destroy.cpp`: goals are the enemy's spawn-room thresholds and the point; with the round won, it attacks any threat ("Chasing down the losers") | `SeekAndDestroy`, `Hunt.HuntGoal`. The threshold comes for free: routes refuse enemy spawn rooms, so a route to a losing spawn ends at its door |
| `tf_bot_tactical_monitor.cpp:167`: round won; winners hunt; losers retreat from any known threat, otherwise crouch | the `humiliation` phase, `SeekAndDestroy`, `Humiliated` fleeing and hiding (no crouch: §7) |

Sandcastle's own additions are the Commander stance and damping, squads and
lanes for `assault`, staging for a locked hill, and the clock-aware KOTH
stances.

## 2. Architecture

### 2.1 Files

| Layer | File | Status |
|---|---|---|
| Model | `G/foundation/aiwar/scenario.lua` | new: the Strategy template, `For`, damping |
| Model | `G/foundation/aiwar/scenario/payload.lua` | new: today's payload allocation, moved behind the interface |
| Model | `G/foundation/aiwar/scenario/control_points.lua` | new: objectives, stances and the point doctrine |
| Model | `G/foundation/aiwar/scenario/koth.lua` | new: extends control_points |
| Model | `G/foundation/aiwar/hunt.lua` | new: the sighting board, hunt goals, flee spots |
| Model | `G/foundation/aiwar.lua` | edit: job constants, the humiliation phase, `War:AssignStances`, `war.hunt` |
| Model | `G/foundation/aiwar/orders.lua` | edit: doctrine lookup, new optional role fields, `SeekAndDestroy`, fleeing `Humiliated` |
| Model | `G/foundation/aiwar/lanes.lua` | edit: `JOBS.assault` |
| Model | `G/foundation/aiwar/posts.lua` | edit: `ScoreGuard` |
| Controller | `G/features/aiwar/sv.lua` | edit: scenario selection, point snapshot, posts, gates and lanes through the scenario, the winner |
| Controller | `G/features/capture/sv.lua` | edit: `HudPoints()`, `AreaEntities(point)` (read-only) |
| Shared | `G/wetsand/sh_aiwar.lua` | edit: help text only |

No entity changes. The soldier port (`soldier.lua`) gains no methods: every
new behaviour uses `MoveTo`, `Hold`, `CoverSpot`, `PatrolSpot`,
`EnemyPosition` and routes.

### 2.2 The controller's think, in order

```
phase  = AiWar.PhaseOf(WETSAND.Active(), WETSAND.State(), self.winner)
field  = self:Field(phase)                      -- snapshot: carts, points, clocks, bases, spawns, winner…
self.scenario:Command(self.war, field, now)     -- Brief (objectives, doctrine) + Allocate (stances)
if field.setup and self.gates == nil then self:FindGates(field) end   -- via scenario:SetupAttacks
self:GuardPosts(field)                          -- posts round each team's guard point (points only)
self:UpdateLanes(field, now)                    -- front via scenario:Front
self.war:SetField(field)
reinforce, update soldiers … (unchanged)
```

Today's `self.war:Assign(self:CartTeams(field.carts))` is replaced by
`Command`. The payload variant's `Allocate` makes exactly that call, with
`CartTeams` moved into the variant.

### 2.3 Scenario (package A): `foundation.aiwar.scenario`

```lua
local require, setmetatable, ipairs = require, setmetatable, ipairs
local Teams = require("foundation.teams")
module(...)

ALLOCATION_HOLD = 3 -- docs/aiwar-command.md §2.2

-- foundation.rounds Mode NAMEs -> the variant module, required on first use
-- so a map loads only its own scenario.
VARIANTS = {
	payload = "foundation.aiwar.scenario.payload",
	control_points = "foundation.aiwar.scenario.control_points",
	koth = "foundation.aiwar.scenario.koth",
}

function For(modeName)            -- -> the variant's Scenario class, or nil

Scenario = { NAME = "none" }
function Scenario:Extend(name)    -- a variant inheriting what it does not override
function Scenario:New()           -- instance: { memory = {}, pending = {}, current = {} }
function Scenario:Reset()         -- a new round: clears pending/current; variants clear their memory

-- The Commander's tick (template method).
function Scenario:Command(war, field, now)
	self:Brief(field, now)
	self:Allocate(war, field, now)
end

-- Variants fill these; the base raises "not implemented".
function Scenario:Brief(field, now)        -- sets field.doctrine and the variant's own field parts
function Scenario:Stances(field, now)      -- -> { [team] = { stance, key, critical } or nil }, { [team] = defense share or nil }
function Scenario:Front(field, team)       -- -> pos or nil: where the team's lanes lead
function Scenario:SetupAttacks(field)      -- -> { [team] = pos }: teams that come out through setup gates, and what they head for

-- Default Allocate: for each team, a stance whose key differs from the
-- current one waits until the same key has been seen for ALLOCATION_HOLD s,
-- unless it is critical or the team has no stance yet. A nil entry leaves
-- the team as it is. Then war:AssignStances(chosen, defense).
function Scenario:Allocate(war, field, now)
```

A stance is today's shape, a list of `{ role, weight }` with integer
weights, first on a tie. `key` is a string that names the situation, and
equal keys mean the same stance table (memoised, as `AiWar.Stance` does).

**Payload variant** (`scenario/payload.lua`, package A):
- `MODE = "payload"`.
- `Brief` sets `field.doctrine = Orders.PAYLOAD`.
- `Allocate(war, field)` is `war:Assign(self:CartTeams(field.carts))`, with no
  damping, as today.
- `CartTeams(carts)` is a pure port of the controller's `CartTeams`. It keeps
  the `CartClose` hysteresis in `self.memory.cartClose`.
- `Front` is the team's own cart, else the enemy's (today's `UpdateLanes`).
- `SetupAttacks` returns each team with a cart when the enemy has none,
  heading for its next checkpoint (today's `FindGates` rule).
- `Reset` keeps `cartClose`, which the controller never reset.

### 2.4 The field: what the controller adds

Every payload field stays as it is. The snapshot adds these fields (package
C) on every map:

| Field | Shape | Source |
|---|---|---|
| `points` | rank-ordered list of snapshots (below), or `nil` when `capture` is not loaded | `capture:HudPoints()`, `capture:AreaEntities(point)` |
| `clocks` | `{ [team] = { left, running } }` or `nil` | `rounds:TeamClock(team)`, `rounds:TimerOf(clock):TimeRemaining(now)`, `:Paused()` |
| `timeLeft` | seconds, or `nil` | `rounds:HudTimer()` → `TimerOf` → `TimeRemaining` |
| `overtime` | bool | `WETSAND.InOvertime()` |
| `bases` | `{ [team] = pos }`: the centroid of the team's spawn points, on the ground | `WETSAND.SpawnPoints(team)`, cached per round |
| `spawns` | `{ [team] = { pos… } }` | same |
| `winner` | the round's winner (RED or BLU) during `TEAM_WIN`, else `nil` | the `WetsandRoundWin` hook; cleared in `RespawnAll` |

A point snapshot, which is what a player's HUD shows (`HudPoint`, pass 4
§2.3), plus where the point is:

```lua
{
	id = <point entity, opaque>,
	rank = 0,                     -- 0-based, capture:Rank
	pos = { x, y, z },            -- the point's origin, on the ground
	zone = { center = { x, y, z }, radius = r } or nil,  -- union AABB of its enabled trigger_capture_areas:
	                              -- center on the ground; r = ZONE_INSET (0.8) x the smaller horizontal half extent;
	                              -- nil when the point has no area (it can be neither a target nor a guard)
	owner = team,                 -- Teams.UNASSIGNED when neutral
	locked = bool, unlockAt = time or nil,
	capping = team,               -- UNASSIGNED when nobody caps
	progress = 0..1, blocked = bool,
	mayCapture = { [RED] = bool, [BLUE] = bool },  -- hud.redCanCap / blueCanCap: the area lets it and TeamMayCapture holds (in-round, order, owner)
	inRound = bool, hidden = bool,
}
```

The scenario's `Brief` adds (package B for points):

- `field.doctrine`
- `field.objectives = { [team] = Objectives }` (§2.5)
- `field.defense = { [team] = share }`. `War:SetField` keeps writing
  `field.defense` from `war.defense`, which `AssignStances` now sets.

### 2.5 Objectives (package B, `scenario/control_points.lua`)

```lua
-- For each team, from field.points, field.bases, field.timeLeft, field.overtime,
-- and the scenario's memory (per point id: lastContestedAt, lastOwner; per team: lostAt):
Objectives = {
	attack = { point… },   -- inRound, zone, not hidden, mayCapture[team]            (CollectCapturePoints)
	defend = { point… },   -- inRound, zone, not hidden, owner == team, mayCapture[enemy] (CollectDefendPoints)
	target = point or nil, -- attack: the one team is capping; else the nearest to bases[team]  (SelectPointToCapture)
	staging = point or nil,-- no attack: the in-round, zoned, locked point not ours, nearest bases[team] ("wait for the unlock")
	guard = point or nil,  -- defend: a threatened one first; else the one nearest bases[enemy] (the forward one)
	focus = point or nil,  -- target or staging (offense), else guard: where chases are leashed
	threatened = bool,     -- guard.capping == enemy, or now - lastContestedAt(guard) < CONTESTED_MEMORY, or justLost
	justLost = bool,       -- now - lostAt[team] < JUST_LOST_TIME (a point we owned is now the enemy's)
	capping = bool,        -- target.capping == team
	timeLeft = s or nil,   -- CP: field.timeLeft (KOTH overrides: the enemy's clock)
	urgent = bool,         -- overtime, or timeLeft < MUST_PUSH_TIME, or capping
}
```

A point counts as contested in memory whenever its snapshot shows
`capping ~= owner and capping ~= UNASSIGNED`, or `blocked`.

**KOTH overrides** (`scenario/koth.lua`):
- `attack = { hill }` when `hill.owner ~= team`, even while it is locked
  (TF2's special case);
- `defend = { hill }` when it is ours;
- `staging = hill` while it is locked;
- `timeLeft = field.clocks[enemy].left`;
- `urgent` is overtime, or the enemy's clock is below `MUST_PUSH_TIME`, or we
  are capping.

### 2.6 Stances (package B)

**CP.** The defense share `d` is in tenths:

- attack only (A/D attackers): `d = 0`;
- defend only (A/D defenders): `d = 10`;
- both:
  `d = tenths(clamp(DEFENSE_EVEN + POINT_LEAD × (enemy-owned − own-owned in-round points) + (threatened and DEFENSE_THREAT or 0) − (capping and DEFENSE_THREAT or 0), AiWar.DEFENSE_MIN, AiWar.DEFENSE_MAX))`.

The stance mirrors payload's `AiWar.Stance`:

- `capture` weighs 4 per offense tenth and `assault` 3;
- per defense tenth, `defend` weighs 5 and `hold` 2, swapped to `hold` 5 and
  `defend` 2 while threatened or just lost;
- `raid` weighs 20 and `support` 10;
- defense roles come first when `d ≥ 5`;
- a role with weight 0 is left out.

A team with only a staging point takes the attack-only stance, and its jobs
stage. A team with nothing at all gets `nil`: its stance stays as it is. The
stance is critical when `threatened and guard.progress ≥ CRITICAL_PROGRESS`,
or when `justLost`.

**KOTH**, by the hill's state for the team (weights; keys in quotes):

| State | capture | assault | hold | defend | raid | support | critical |
|---|---|---|---|---|---|---|---|
| `"locked"`: hill locked | 4 | 3 | | | 2 | 1 | |
| `"open"`: unlocked, neutral | 5 | 3 | | | 1 | 1 | |
| `"held"`: ours | | | 3 | 4 | 2 | 1 | |
| `"held:turtle"`: ours, own clock ≤ `KOTH_TURTLE_TIME` | | | 4 | 5 | | 1 | |
| `"held:capped"`: ours, enemy capping | | | 6 | 3 | | 1 | when progress ≥ `CRITICAL_PROGRESS` |
| `"lost:<a>"`: theirs; `a` = aggression in tenths = `clamp(round((MUST_PUSH_TIME − enemy clock) / MUST_PUSH_TIME × 10), 0, 10)` | 30 + 4a | 40 − 2a | | | 20 − 2a | 10 | |
| `"laststand"`: theirs, and overtime or enemy clock ≤ `KOTH_LAST_STAND` | 8 | 1 | | | | 1 | yes |

**`War:AssignStances(stances, defense)`** (package A, `aiwar.lua`):
- `stances` is `{ [team] = list or nil }`; `defense` is
  `{ [team] = share or nil }`, which becomes `war.defense`.
- A team with a current stance is rebalanced with the fewest moves
  (`War:Rebalance`, which already handles roles that leave the stance).
- A team without one is assigned from scratch, oldest first.
- A nil entry leaves the team as it is.
- `War:Assign(carts)` keeps its body and meaning.

### 2.7 Doctrine and the point jobs

**The doctrine interface.** Package A implements it in `orders.lua` and
package B implements the point doctrine against it:

```lua
doctrine = {
	NAME = "payload" | "points",
	ROLES = { [job] = role },
	WaitsForSetup = function(field, member) -> bool,     -- wander behind the gates in setup
	ChaseAnchor = function(field, member) -> pos or nil,  -- chases keep within CHASE_LEASH of it; nil: no leash
	PatrolMark = function(field, member) -> mark,        -- taken when a patrol starts
	PatrolHolds = function(mark, field, member) -> ok, why,  -- the patrol goes on while true (orders adds the post-moved check)
}
```

`Orders.PAYLOAD` is today's `ROLES` with today's `WaitingForSetup`, today's
`ChaseCart` as `ChaseAnchor` (the cart's pos), and today's `Anchor` and
`AnchorHolds` cart checks as `PatrolMark` and `PatrolHolds`.

**A role**, today's shape with its existing fields unchanged:
- existing: `name`, `arrive`, `leash`, `rushes`, `Goal`, `sits`, `chases`,
  `follows`, `tactic`, `patrols`, `raids`, `Cleared`, `Sphere`, `heals`;
- new and optional, handled generically by package A:
  - `Zone(field, member) -> center, radius | nil`: the area to occupy.
    Inside it the soldier has arrived, and it walks to a new
    `PatrolSpot(center, radius)` every `ZONE_SHUFFLE` s (TF2 re-paths on the
    point every 0.5–1 s).
  - `Urgent(field, member) -> bool`: while true, the soldier travels at
    `RUSH`, does not stop to engage at its leash, starts no chases, and
    answers `ShouldRetreat` NO and `ShouldHurry` YES (TF2
    `CTFBotCapturePoint`).
  - `Line(field, member) -> line, from | nil`: a raider's enemy line. The
    payload `RAID` role sets it to `EnemyLine`. `RaidGoal` and `Fight` call
    `role.Line`, not `EnemyLine`.
  - `gait`: a trip gait that overrides `WALK` for spot trips. The hunt and
    hide trips use `RUN`.

**The point doctrine** (package B, `ControlPoints.DOCTRINE`, `NAME =
"points"`). `o` is `field.objectives[member.team]`. Every job reads only
`o`, `field.points`, `field.posts`, `field.gates`, `field.bases`,
`field.setup` and `field.defense`, never `field.carts`.

| Job (`AiWar.*`) | Describe name | Goal | Other fields |
|---|---|---|---|
| `CAPTURE` | `CapturePoint` | target unlocked: `Ring(zone.center, slot, zone.radius × CAPTURE_SPREAD)`. Locked target or staging: `Ring(Toward(zone.center, bases[team], zone.radius + STAGE_DISTANCE), slot, STAGE_SPREAD)`. Neither: `HOLD`'s goal (TF2: CapturePoint → DefendPoint) | `Zone` = the target's zone when unlocked; `Urgent` = `o.urgent` or within `NEAR_POINT` of the target; arrive 48, leash 300 |
| `ASSAULT` | `Assault` | `EntryPoint` of its sphere from `member.pos`. The sphere is centred on `Toward(zone.center, bases[team], ASSAULT_STANDOFF)` of the target or staging point, with radius `ASSAULT_SPHERE`. Neither: `DEFEND`'s goal | `Sphere`, `tactic = "attack"`, `chases = "opportunist"`; lanes (`Lanes.JOBS.assault`); arrive 150, leash 700 |
| `HOLD` | `HoldPoint` | guard threatened, or setup for a defender: `Ring(zone.center, slot, zone.radius × CAPTURE_SPREAD)`. Otherwise `Ring(zone.center, slot, zone.radius + HOLD_RING)`. No guard: `CAPTURE`'s goal | `Zone` = the guard's zone while threatened or in setup; `Urgent` = `o.threatened`; shotgun kit; arrive 72, leash 200 |
| `DEFEND` | `DefendPoint` | setup: `GateSpot(field, member, 0)`. Otherwise `field.posts[team][slot + 1]`, then `Ring(Toward(guard center, bases[enemy], DEFEND_RING), slot, DEFEND_SPREAD)`. No guard: `ASSAULT`'s goal | `tactic = "defend"`, `patrols = true`, `chases = "opportunist"`; arrive 150, leash 900 |
| `RAID` | `Raid` | setup: `GateSpot(field, member, 0)`. Otherwise `Tactics.FlankPoint(from, line, slot parity side)` | `Line`: on offense, `line` = the target or staging center and `from` = `bases[team]`; on defense, `line` = the guard center and `from` = `bases[enemy]`. Focus is split by the golden ratio over `field.defense[team]`, as payload's `Focus`. `Cleared`: on offense, `Ring(target zone, slot + 8, …)`; on defense, `Toward(guard center, bases[enemy], RAID_INTERCEPT)`. `raids`, `tactic = "raid"` |
| `SUPPORT` | `Support` | setup: `GateSpot(field, member, GATE_ROW × 2)`. Otherwise `Toward(focus center, bases[team], zone.radius + Orders.SUPPORT_BEHIND)`, spread by `Lateral(slot)` | `tactic = "support"` |
| `MEDIC` | `Medic` | `SUPPORT`'s goal | `heals = true` |

The rest of the doctrine:
- `WaitsForSetup(field, member)`: `field.setup` holds, the team has a target
  or staging point, and it has no guard. These are the A/D attackers, who
  wander behind their gates as payload attackers do.
- `ChaseAnchor` is `o.focus`'s zone center.
- `PatrolMark` is `{ guard = o.guard and o.guard.id }`.
- `PatrolHolds` holds while the guard is unchanged and `not o.threatened`.

To serve package B, package A turns these `orders.lua` locals into module
functions: `Ring`, `Lateral`, `GateSpot`, `Behind` and `EntryPoint`.
`Across`, `InSphere` and `SupportSphere` are already public.

### 2.8 Orders, generically (package A)

The edits to `orders.lua` are listed by the payload-specific line each one
replaces (line numbers on 9e75e34):

| Where | Change |
|---|---|
| `Goal` (434), `Travel:Goal` (679) | `DoctrineOf(field).ROLES[...]` |
| `WaitingForSetup` calls (673, 680, 903) | `DoctrineOf(field).WaitsForSetup(field, member)` |
| `ChaseCart`, `Leashed` (753–761) | `DoctrineOf(field).ChaseAnchor` |
| `Anchor`, `AnchorHolds` (862–873) | the post-moved check stays; the rest is `PatrolMark` and `PatrolHolds` |
| `Objective:Update` follow (921) | `OwnCart` is evaluated only for a role with `follows` |
| `RaidGoal` (1002), `Fight` (1149) | `self.role.Line(field, member)` |
| `ObjectiveFor`, `OBJECTIVE_OF` | one class per (doctrine, job), memoised; `Objective:Update` changes to a new class when the job **or** the doctrine differs |
| new | `Zone`/`Urgent`/`gait` handling in `Travel:Update` and `Objective:Update`; `Objective:ShouldRetreat` and `Objective:ShouldHurry` from `Urgent`; `Roam(me, center, radius, rest)` gains its rest argument (default callers pass `ROAM_REST`) |

`DoctrineOf(field)` is `field.doctrine`, with no fallback. The test fixtures
set it.

### 2.9 Post-round carnage (package A)

`foundation.aiwar`:
- adds `PHASES.humiliation = { name = "humiliation", reinforce = false,
  orders = true, hunt = true }`;
- gives every other phase `hunt = false`;
- `PhaseOf(active, state, winner)` returns `humiliation` for
  `STATE.TEAM_WIN` with a winner in `{ RED, BLUE }`, and `over` otherwise.

`War.New()` adds `hunt = Hunt.Board.New()`.

`foundation.aiwar.hunt` (pure):

```lua
HUNT_MEMORY = 10          -- a sighting of a loser is followed this long
HUNT_ARRIVE, HUNT_GIVE_UP = 96, 12
FLEE_COVER, FLEE_REPICK, HIDE_ARRIVE = 600, 256, 160
Board.New()
board:Report(team, subject, pos, now)       -- a soldier of team saw subject (enemy handle) at pos
board:Sightings(team, now) -> { { subject, pos, time }… }   -- within HUNT_MEMORY, newest first
Quarry(sightings, here) -> sighting or nil  -- the nearest
HuntGoal(field, member, sightings, here) -> pos or nil
	-- the Quarry's pos; else field.spawns[loser][member.slot % #spawns + 1]: routes refuse enemy
	-- spawn rooms, so the trip ends at its door (TF2's spawn-room thresholds); nil without spawns
Hideout(field, member, here) -> pos or nil  -- the nearest of field.spawns[member.team]
```

`orders.lua`:
- **`Hunting(field, member)`** is `field.phase.hunt and field.winner ==
  member.team`.
- **`TacticalMonitor:Update`** keeps its disarmed check first, then
  `Hunting` → `SuspendFor(SeekAndDestroy:New(state), "get the losers")`, then
  its retreat check.
- **`RetreatToCover:Update`** ends with `Done` when the soldier is disarmed
  or hunting, so the monitor above can take over.
- **`SeekAndDestroy`** (TF2 `CTFBotSeekAndDestroy`):
  - `Done("the round is over")` when not `Hunting`;
  - with an enemy in sight, it reports the sighting to `war.hunt`, runs at
    the enemy (`MoveTo(EnemyPosition, RUN)`), and holds once within
    `HUNT_CLOSE` (300);
  - with none in sight, it goes to `HuntGoal` as a `Travel` spot trip (role
    `HUNT = { name = "Hunt", arrive = HUNT_ARRIVE, leash = 0, rushes =
    false, giveUp = HUNT_GIVE_UP, gait = RUN }`), kept while `Hunting` and
    no enemy is in sight;
  - it answers `ShouldRetreat` NO and `ShouldHurry` YES.
- **`Humiliated`** keeps its name, `ShouldAttack` NO, `ShouldHurry` YES and
  its "rearmed" end. Its `Update` gains:
  - with an enemy in sight, it flees to
    `CoverSpot(here, FLEE_COVER, threat)`, else to
    `Behind(here, threat, RETREAT_DISTANCE)`;
  - it re-picks when the threat has moved `FLEE_REPICK` or the spot is
    reached;
  - with no enemy in sight, it takes a `Travel` trip to `Hideout` (role
    `HIDE`, gait `RUN`) and `Hold`s within `HIDE_ARRIVE`;
  - with no hideout, it holds.

### 2.10 Controller (package C, `features/aiwar/sv.lua`)

**Start** (replaces the `team_train_watcher` refusal):
- `modeName` = `RoundsModeName()`: the rounds mode's `NAME` when `"rounds"`
  is in `WETSAND.FeatureLoader:Loaded()`, else nil.
- `variant = Scenario.For(modeName)`; refuse with §0.1's message when it is
  nil.
- `self.scenario = variant:New()`.
- The rest of `Start` is unchanged, including `Request(GAMEPLAY,
  SOURCE_AI_WAR, …)`.

**Field** adds the fields in §2.4:
- `PointsSnapshot()`, `Clocks(now)`, `timeLeft`, `overtime`, `bases`,
  `spawns` (cached until `RespawnAll`) and `winner`.
- The capture and KOTH queries run only when their feature is already
  loaded.
- `ZONE_INSET = 0.8` is a named local.

**Think** follows §2.2. `CartTeams` is deleted: it moved to the payload
variant.

**The scenario seams:**
- **`FindGates`:** targets come from `self.scenario:SetupAttacks(field)`,
  and the route and door logic is unchanged.
- **`UpdateLanes`:** the front is `self.scenario:Front(field, team)`.
- **`GuardPosts(field)`:** for each team whose `field.objectives[team].guard`
  is set:
  - the candidates are `CandidateSpots(zone.center, Posts.MAX_GUARD_RANGE)`;
  - each candidate records `{ pos, sees, toPoint, elevation, cover, sniper,
    past = dist(base, spot) − dist(base, zone.center), anywhere =
    self.scenario.GUARDS_ALL_ROUND }`;
  - it picks with `Posts.Pick(…, Posts.ScoreGuard)` and caches by
    `"guard"`, team and guard rank;
  - it writes `field.posts[team]` only when payload wrote none.

**Rounds:**
- The `WetsandRoundWin` hook sets `self.winner` to the winner when it is RED
  or BLU, else nil, alongside today's `Humiliate`.
- `RespawnAll` clears `self.winner`, the base cache and the guard-post
  cache, and calls `self.scenario:Reset()`.

**Kits:** `KITS[team][AiWar.HOLD] = BLOCKER_KIT` for both sides.

**Report:** `wetsand_aiwar_report` adds one line per team: the scenario
`NAME`, the stance key, and the ranks of target, guard and staging.

**`features/capture/sv.lua`** gains two queries. Both are additive, and the
published keys are unchanged.
- `Controller:HudPoints()` returns `{ { point, rank, hud }… }` in rank
  order, with the same `hud` tables `PublishPoints` builds; `PublishPoints`
  publishes from it.
- `Controller:AreaEntities(point)` returns the point's enabled
  `trigger_capture_area` entities.

**`wetsand/sh_aiwar.lua`:** `HELP` and the `mp_aiwar_start` help say
"Payload, control point and King of the Hill maps" and drop "defending the
cart".

## 3. Constants (new; each named once, in its owner)

| Owner | Name | Value | Source |
|---|---|---|---|
| `foundation.aiwar` | `CAPTURE, ASSAULT, HOLD` | `"capture", "assault", "hold"` | aiwar-command §2.2 and §8.7 (`assault`, `hold`) |
| `foundation.aiwar.scenario` | `ALLOCATION_HOLD` | 3 | aiwar-command §2.2 |
| `…scenario.control_points` | `MUST_PUSH_TIME` | 120 | `tf_bot_offense_must_push_time` |
| | `NEAR_POINT` | 750 | `tf_bot_near_point_travel_distance` |
| | `CONTESTED_MEMORY` | 5 | `LastContestedAt` window, `tf_bot_defend_point.cpp` |
| | `JUST_LOST_TIME` | 15 | `m_justLostPointTimer` 10–20 s, `tf_bot.cpp:1682` |
| | `CRITICAL_PROGRESS` | 0.5 | `tf_bot_defend_owned_point_percent` |
| | `DEFENSE_EVEN, POINT_LEAD, DEFENSE_THREAT` | 0.5, 0.1, 0.2 | Sandcastle (mirrors `AiWar.DEFENSE_*`) |
| | `CAPTURE_SPREAD, STAGE_DISTANCE, STAGE_SPREAD` | 0.6, 400, 160 | Sandcastle |
| | `ASSAULT_STANDOFF, ASSAULT_SPHERE` | 300, 700 | Sandcastle (escort sphere analogue) |
| | `HOLD_RING, DEFEND_RING, DEFEND_SPREAD, RAID_INTERCEPT` | 160, 500, 200, 900 | Sandcastle |
| `…scenario.koth` | `KOTH_LAST_STAND, KOTH_TURTLE_TIME` | 30, 30 | Sandcastle |
| | `GUARDS_ALL_ROUND` | true (CP: false) | TF2 skips the incursion limit in KOTH |
| `foundation.aiwar.posts` | `MAX_GUARD_RANGE` | 1250 | `tf_bot_max_point_defend_range` |
| | `PAST_POINT_LIMIT, GUARD_TOO_LOW` | 250, 220 | `CSelectDefenseAreaForPoint` |
| `foundation.aiwar.orders` | `ZONE_SHUFFLE, HUNT_CLOSE` | 1, 300 | 0.5–1 s re-path on the point; Sandcastle |
| `foundation.aiwar.hunt` | `HUNT_MEMORY, HUNT_ARRIVE, HUNT_GIVE_UP, FLEE_COVER, FLEE_REPICK, HIDE_ARRIVE` | 10, 96, 12, 600, 256, 160 | Sandcastle |

## 4. Work packages

Packages run in waves; within a wave, file ownership is disjoint.

| Pkg | Wave | Depends on | Owns: creates (+) or edits (~) |
|---|---|---|---|
| **A: seam, orders, carnage** | 1 | none | +`G/foundation/aiwar/scenario.lua`, +`G/foundation/aiwar/scenario/payload.lua`, +`G/foundation/aiwar/hunt.lua`, ~`G/foundation/aiwar.lua`, ~`G/foundation/aiwar/orders.lua`, ~`G/foundation/aiwar/lanes.lua`, ~`tests/fake_soldier.lua` (only if needed), +`tests/aiwar_scenario_test.lua`, +`tests/aiwar_carnage_test.lua`, ~`tests/aiwar_orders_test.lua`, ~`tests/aiwar_test.lua`, ~`tests/aiwar_lanes_test.lua` |
| **B: point scenarios** | 2 | A | +`G/foundation/aiwar/scenario/control_points.lua`, +`G/foundation/aiwar/scenario/koth.lua`, ~`G/foundation/aiwar/posts.lua`, +`tests/fake_points.lua`, +`tests/aiwar_points_test.lua`, +`tests/aiwar_koth_test.lua`, ~`tests/aiwar_posts_test.lua` |
| **C: controller** | 2 | A | ~`G/features/aiwar/sv.lua`, ~`G/features/capture/sv.lua`, ~`G/wetsand/sh_aiwar.lua`, ~`docs/aiwar-command.md` (a short §11 "Scenarios" pointing here) |
| **I: integration** | 3 | B, C | no files. It runs §6; each defect goes back to the package that owns the file |

Every package:
- merges origin/main first;
- writes each test before its code and watches it fail;
- commits with `git -c gpg.program=gpg-loopback commit`;
- never stages `G/features/gamemode/sv.lua`.

### 4.1 Acceptance, every package

- `sh .devtools/bin/run_lua_tests.sh` exits 0, and every file reports
  `0 failed`.
- `sh .devtools/bin/check_lua.sh` compiles every file.
- `python3 .devtools/bin/check_names.py` prints `ok`.
- `luajit -b <file> /dev/null` succeeds for every changed Lua file.
- `git diff --name-only origin/main...HEAD` lists only files the package
  owns.

### 4.2 Package A

| # | Criterion | Check |
|---|---|---|
| A1 | Payload unchanged: every pre-existing test in `tests/aiwar_*_test.lua` passes, and `git diff` of `tests/aiwar_orders_test.lua` changes existing tests only by adding `doctrine = Orders.PAYLOAD` to field fixtures | run the suite; read the diff |
| A2 | `Scenario.For("payload")` is the payload variant; `For("none")` and `For(nil)` are nil; `VARIANTS` keys equal the rounds modes' `NAME`s (the test requires `foundation.rounds.payload`, `.control_points` and `.koth` and compares `Mode.NAME`) | `tests/aiwar_scenario_test.lua` |
| A3 | The payload variant's `Command` on a race field gives the same roles per member as `war:Assign(CartTeams)` did, including `CartClose` hysteresis across ticks (remaining 1000 is close, 1300 stays close, 1500 is not: `CLOSE_RANGE` 1024 + `CLOSE_HYSTERESIS` 384) | same file |
| A4 | Damping with a test variant: a new key waits `ALLOCATION_HOLD` s before `AssignStances`; a critical one applies at once; the first stance applies at once; a nil entry leaves the team alone | same file |
| A5 | `War:AssignStances` rebalances with the fewest moves when roles leave the stance: 8 soldiers moving from {capture, assault, raid, support} to {hold, defend, raid, support} keep raid and support members, and move only capture and assault members | `tests/aiwar_test.lua` |
| A6 | `PhaseOf(true, STATE.TEAM_WIN, BLUE)` is `PHASES.humiliation`; with `nil` or `UNASSIGNED` it is `PHASES.over`; every phase has a boolean `hunt` | `tests/aiwar_test.lua` |
| A7 | Doctrine seam: with a stub doctrine in the test whose one job has `Zone`, `Urgent` and no `carts` in the field, a soldier travels into the zone, then walks between `PatrolSpot`s in it every `ZONE_SHUFFLE`; with `Urgent` true its gait is `RUSH`, it does not stop at its leash with an enemy in sight, and `npc:Query("ShouldRetreat")` is NO | `tests/aiwar_orders_test.lua` (new tests) |
| A8 | Changing `field.doctrine` changes the job's action class (Describe shows the new doctrine's name) | same |
| A9 | Carnage, winners: in `humiliation` with `winner = BLUE`, a BLU soldier's Describe is `SoldierAction/StrategyMonitor/SeekAndDestroy` (plus `/Travel` on a trip); with an enemy in sight it moves at it and its sighting is on `war.hunt`; a second BLU soldier with no enemy travels to that sighting; with none, it travels to `field.spawns[RED][slot % n + 1]` | `tests/aiwar_carnage_test.lua` |
| A10 | Carnage, losers: a disarmed RED soldier with an enemy in sight moves to the fake's cover spot away from the threat (else `Behind`); with no enemy it travels to its nearest own spawn and holds within `HIDE_ARRIVE`; `ShouldAttack` is NO throughout; the existing test at `aiwar_orders_test.lua:180` still passes | same |
| A11 | It ends at the next round: switching the field to `PHASES.frozen`, then `running`, gives `SeekAndDestroy` Done and the soldier's job action back; a soldier in `RetreatToCover` when the hunt begins leaves it within one tick | same |
| A12 | Stalemate: `winner = nil` in `TEAM_WIN` means no soldier hunts (phase `over`, orders off, as today) | same |

### 4.3 Package B

`tests/fake_points.lua` builds point snapshots and fields:
- `FP.Point{ rank, at, radius, owner, locked, capping, progress, blocked,
  mayCapture, inRound }`;
- `FP.Field{ phase, points, clocks, timeLeft, overtime, bases, spawns, setup,
  gates, posts }`.

The full-stack tests below run `War` + scenario `Command` + `Orders` +
`tests/fake_soldier.lua` soldiers, as `aiwar_orders_test.lua`'s `Enlist`
does.

| # | Scenario test | File |
|---|---|---|
| B1 | `Objectives` reproduce `CollectCapturePoints` and `CollectDefendPoints`: points out of round, hidden, or without a zone are never attack or defend; the owner's point is defend only when `mayCapture[enemy]` | `aiwar_points_test.lua` |
| B2 | Target choice: the point we cap first, else the nearest to our base; staging is the locked point not ours, nearest our base | same |
| B3 | Threat memory: contested at t is threatened until t + `CONTESTED_MEMORY`; a point we owned turning enemy sets `justLost` for `JUST_LOST_TIME`; `Reset` clears it (a round reset is no loss) | same |
| B4 | CP stances: A/D attackers get only offense roles and defenders only defense roles; 5CP with both follows `d`; the hold/defend swap while threatened; critical at progress ≥ 0.5 | same |
| B5 | Every point job's `Goal` with no `carts` in the field returns the §2.7 spot, including every fallback (no target → hold's goal; no guard → capture's) | same |
| B6 | Full stack, 5CP: RED owns 0–1, BLU owns 3–4, mid neutral and capturable by both: capture soldiers end inside mid's zone and shuffle; after BLU takes mid (RED's point 1 now capturable by BLU), RED's `DEFEND` goals are `field.posts[RED]` round point 1 and RED's hold soldiers stand on point 1 while BLU caps it | same |
| B7 | Full stack, A/D setup: BLU (attack only) wanders (`WaitsForSetup`); RED defenders stand at `GateSpot`s and RED hold soldiers in point A's zone; when setup ends, BLU capture soldiers travel to A (lane leaders on lanes) | same |
| B8 | Full stack, A/D fall back: A becomes BLU's, so RED's guard becomes B, `justLost` is critical (no damping), and RED's hold soldiers travel to B's zone within 20 ticks | same |
| B9 | Mini-rounds: points with `inRound = false` are never targeted or guarded, even when `mayCapture` would say so | same |
| B10 | KOTH locked opening: capture soldiers go to staging spots outside the zone on their own side; the hill unlocks, and they enter the zone | `aiwar_koth_test.lua` |
| B11 | KOTH clock-aware stances: the key and critical flag follow §2.6 for enemy clocks 170, 100, 60, 25 and overtime; the allocated counts of capture soldiers rise monotonically; `laststand` applies without waiting `ALLOCATION_HOLD` | same |
| B12 | KOTH contest: the enemy owns the hill with its clock at 20, so capture soldiers are `Urgent` (gait `RUSH`, `ShouldRetreat` NO) and occupy the zone | same |
| B13 | KOTH hold: we own the hill and the enemy starts capping, so hold soldiers go from their ring into the zone; with our clock ≤ `KOTH_TURTLE_TIME`, raid leaves the stance | same |
| B14 | `Posts.ScoreGuard`: nil when unseen, beyond 1250, more than 250 past the point unless `anywhere`, or more than 220 below; the higher candidate with cover wins | `aiwar_posts_test.lua` |

### 4.4 Package C

C has no LuaJIT tests: controllers are checked in game (I). Its acceptance:

| # | Criterion | Check |
|---|---|---|
| C1 | No cart refusal remains | `grep -c 'this map has no payload cart' G/features/aiwar/sv.lua` prints 0 |
| C2 | The scenario is picked only from the mode, never from a map name | `grep -nE 'game.GetMap|"(koth|cp|pl)_' G/features/aiwar/sv.lua` prints nothing |
| C3 | `CartTeams` has left the controller | `grep -c 'function Controller:CartTeams' G/features/aiwar/sv.lua` prints 0 |
| C4 | The capture additions are read-only | `git diff G/features/capture/sv.lua` adds only `HudPoints`, `AreaEntities` and `PublishPoints` publishing from `HudPoints`; the published key names are identical |
| C5 | §4.1 passes | as listed |

## 5. What "done" looks like

After the three waves:

- `run_lua_tests.sh` passes the baseline's 1048 tests plus A's and B's new
  tests, with 0 failures.
- The §6 in-game checklist passes on the maps named there.
- Payload plays as before.

## 6. In-game checklist (integration, after B and C merge)

Setup for every map:
- DrGBase loaded;
- `mp_aiwar_team_size 8`;
- `wetsand_aiwar_debug` on;
- `wetsand_aiwar_report` in the console for each check.

To force a win, use `ent_fire team_control_point_master setwinner 3`, where
3 is BLU.

**Payload regression**
1. `pl_badwater`: the war behaves as before. Pushers ride, defenders post,
   and the report shows the scenario `payload`.
2. `plr_hightower`: the race works as before.

**KOTH**
3. `koth_viaduct`, started from Sandbox mode with `mp_aiwar_start`:
   - the countdown runs, then Gameplay mode begins;
   - during the 30 s lock, both sides stage outside the hill on their own
     side;
   - at unlock, capture soldiers rush onto the hill and shuffle on it;
   - the owner's hold soldiers ring it, and its defenders take posts that see
     it.
4. `koth_viaduct`, clock behaviour:
   - let one side hold the hill;
   - as its clock falls, the report's stance key for the other side moves
     through `lost:<a>` to `laststand`;
   - in overtime, the losing side swarms the hill.
5. `koth_sawmill` (no `tf_gamerules` in the BSP): the war starts, which shows
   that the created proxy supplies the mode.
6. `koth_harvest_final`: the lanes of assault squads differ, as seen in the
   overlay's routes.

**Symmetric CP**
7. `cp_badlands` or `cp_granary`:
   - both sides go for mid;
   - after one side takes it, that side pushes the next point, and the other
     side's hold soldiers stand on its threatened second point;
   - the report shows target and guard ranks changing.

**A/D**
8. `cp_gravelpit`:
   - in setup, RED lines up at BLU's gates and BLU wanders its spawn yard;
   - after setup, BLU pushes A or B (either is capturable), and its lanes
     differ.
9. `cp_dustbowl` (mini-rounds, no `tf_gamerules`):
   - stage 1 behaves as check 8;
   - after stage 1 is won, stage 2's points are the only targets;
   - when point 1 falls, RED's hold soldiers run to point 2 within about 5 s.
10. `cp_egypt_final`: the final point's guard holds with posts that see it.

**Post-round carnage**
11. On any map, force a BLU win:
    - BLU soldiers leave their jobs (Describe shows `SeekAndDestroy`) and
      hunt;
    - they kill fleeing RED soldiers and RED players;
    - RED soldiers do not fire, run from BLU soldiers in sight, and otherwise
      head for their spawn;
    - the next round starts with everyone back on normal orders.
12. With `mp_bonusroundtime 15`, the hunt lasts the whole bonus time; hunters
    stop at RED's spawn doors and never walk into the spawn room.
13. A stalemate (`mp_timelimit` reached with sudden death off): nobody hunts.

**Load**
14. `wetsand_memory` on `cp_badlands` lists `aiwar` only after
    `mp_aiwar_start`. `package.loaded` holds
    `foundation.aiwar.scenario.control_points` but not
    `…scenario.payload` or `…koth`.

## 7. Judgment calls to revisit

1. **Capture state comes from the HUD query**, not from the capture models'
   internals. That keeps §0.6 literal. The cost is two small public queries
   added to another feature's controller.
2. **Hunters know only what they or another hunter saw** (the board), plus
   the losers' spawns. They get no wallhack in humiliation, even though the
   bonus time is short. If hunts feel aimless, the fix is a longer
   `HUNT_MEMORY`, not omniscience.
3. **Losers do not crouch.** TF2 crouches when no threat is known. The port
   has no crouch. Adding `Crouch()` means changing the port, the fake and the
   DrGBase bridge, so it is left out.
4. **A stalemate means no carnage**, which is today's rule. In TF2 a
   stalemate humiliates everyone.
5. **Lanes serve `assault` only.** `capture` goes by the shortest route: it
   is the rush.
6. **A/D is not its own scenario**, per pass 4 decision 3. If A/D defenders
   should behave very differently from 5CP defenders, the place for it is
   the CP stance, which already knows attack-only from defend-only.
7. **The KOTH weights and times** (`KOTH_LAST_STAND`, `KOTH_TURTLE_TIME`, the
   table in §2.6) are Sandcastle's. They can only be tuned in play.
   `MUST_PUSH_TIME` is TF2's 120, which on a 180 s clock makes the team
   without the hill lean in after it has held for about 60 s.
8. **`ZONE_INSET` 0.8 of the smaller half extent** keeps spots inside odd
   rectangular areas at the cost of using less of them.
9. **The damping applies to point scenarios only.** Payload keeps its
   undamped `Assign`, so its behaviour does not move.
10. **No console variable toggles carnage** (§0.9).

## 8. Out of scope

- The full Commander (aiwar-command §2): reports, situations, commands as
  events and suitability-based moves. `Scenario:Command` is where it will
  plug in.
- Kit and job separation (aiwar-command phase 6).
- CTF, player destruction and the cp_carrier hybrid (pass 4 decision 8).
- Arena and `tf_logic_*` minigames: no mode, so the start is refused.
- TF2 incursion distances. Guard posts use distance from the base as their
  stand-in (the memory note on MvM pathing keeps the real ones for later).
