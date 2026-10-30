# Squad missions: the leader waits, asks, leads (issue #4)

The operator's design, from issue #4's comments and the follow-up: a squad
leader spawns and goes to a spot cheaply found, just outside its spawn. It
asks the tactics engine for a mission, as a transaction on the slow lane.
The engine answers with a mission: how many soldiers the squad should be,
where it goes, and how long to wait for its members, from the spawn waves.
While it waits, the leader's head scans the lanes it may take. Then it
signals, calls the squad out, and leads. It carries on unless the squad
takes heavy casualties or cannot progress. Then it signals a regroup, takes
the squad to a hiding spot, and asks again.

Missions are how squads come to do more than walk a lane: an ambush set
for a room the enemy will come through, an assault on a room known to be
heavily guarded, toppling an enemy support base. The first mission kind is
today's (advance along a lane). The others need what the squads do not yet
know, and come later (§6).

It is the first real user of the slow lane (`WS.SlowTransactions`,
`foundation.transaction`'s `Spawn`/`Within`), and it should take load off
the tick. Today `War:Assign` gives every squad a lane on every update
(`wartactics.lanes.Assign`). After this, lanes are given when a leader asks.

## 1. The loop

```
Muster ──ask──▶ Waiting ──mission + (members in, or wait elapsed)──▶ Leading
  ▲                                                                   │
  └──────── Regrouping (to a hiding spot) ◀── heavy casualties ───────┘
                                          ◀── no progress
Leading ──the engine replaces the mission──▶ Halt (signal) ──▶ Leading the new one
```

- **Muster.** The leader walks to its spawn's threshold: the centre of the
  nearest nav area outside its own spawn room, which `wartactics.lanes`
  already finds for the enemy's spawn (`Threshold`, over
  `npcs:SpawnRoomTeam`). Asked of its own team's room, it is the same
  walk. It is found once per spawn room per round and kept, as
  `roomExits` keeps the enemy's.
- **Ask.** On arriving, the leader asks for a mission. That is one
  transaction on the slow lane, and a leader has at most one in flight.
- **Waiting.** It holds at the muster spot, its members gathering on it in
  their battle stance (`Pose`). Its head looks down each lane's first leg
  in turn (the soldier port's new `LookAt`, through `nextsoldier.gaze`'s
  hint). It aims at nothing. It waits until the mission has come and either
  the squad is the size the mission asks or the wait has elapsed.
- **Leading.** It signals forward (`nextsoldier.gestures`' `SIGNAL_FORWARD`)
  and calls out (a new concept, `TLK_NS_MOVE_OUT`). Then the squad runs the
  mission as it runs its lane today (bounds, contact, regrouping on a far
  leader).
- **Regrouping.** On heavy casualties (the squad down to
  `CASUALTY_SHARE` of the mission's size), or no progress (`STUCK_TIME`
  without getting `PROGRESS_STEP` closer along the mission's way, or no
  route), it signals a group (`SIGNAL_GROUP`) and calls out
  (`TLK_NS_REGROUP`). It leads the squad to a hiding spot (the port's
  `CoverSpot` away from the last contact), and asks again from there:
  the muster spot is wherever it hides.
- **Halt.** The engine may replace a squad's mission while it is led (the
  `aiwar-command.md` command channel: an event down to the squad). The
  leader signals halt (`SIGNAL_HALT`) and leads the new one, with no wait.

A member does as today, and also gathers on its leader while the leader
waits. A soldier with no squad (solo) asks nothing and keeps today's orders.

## 2. The mission and the wait

`wartactics.mission`, a pure model (wartactics types, tested under LuaJIT):

- `Mission{ kind, way, size, wait, issued }`: made only by its factory,
  which refuses a kind it does not know, a way without points, a size
  under 1, or a negative wait. `kind` is `ADVANCE` for now. `way` is the
  waypoints (a lane, as `wartactics.lanes` gives them). `size` is the
  soldiers the squad should be. `wait` is in seconds from `issued`.
- `Wait{ missing, nextWave, now, travel }`: how long the leader waits for
  its members. If none is missing, there is no wait. After spawning, it is
  the time to its team's next wave (`War.nextWave`, which
  `War:Reinforcements` keeps) plus their walk from spawn to the muster spot
  (`travel`, the distance over a soldier's run speed). After a regroup (no
  `nextWave`), it is only the walk of the living. It is held to `WAIT_MAX`.
- `Casualties(mission, alive)` and `Track(remaining, now)`'s
  `Stuck(remaining, now)`: whether the squad must regroup. A track is the
  squad's record of its best distance left along the way, and when.

Tuning (`WAIT_MAX`, `CASUALTY_SHARE`, `STUCK_TIME`, `PROGRESS_STEP`) is
defined and tested for being defined; the tests derive from it.

## 3. The request on the slow lane

`features/aiwar/sv_missions.lua`, a controller part:

- **The alpha squad comes first.** Each team always has one alpha squad,
  tending the objective directly: the direct lane to its front (pushing or
  guarding the cart, taking or holding the point). Every other mission is
  secondary to it. A request from a team with no alpha squad makes the
  asking squad its alpha, whatever it was given before. When the alpha
  squad is wiped out or regroups, the next squad to ask becomes the alpha.
  A special mission (§6) is only ever given to a squad other than the
  alpha, and only while the alpha squad is out on its mission.
- `Controller:RequestMission(fireTeam)` → a transaction, at most one per
  squad: `Transaction.Spawn(WS.SlowTransactions, ...)` with a
  `:Within(WS.Deadline(MISSION_TIME))`. Its work reads the field, decides
  whether the squad is the alpha, chooses the squad's lane (the alpha: the
  direct lane; any other: the least taken of its job's kinds, as
  `Lanes.Assign` does now, for one squad), computes the wait, and commits a
  `Mission`. It
  yields (`work:CheckYield`) between squads' worth of work. It never plans
  lanes itself: lane planning stays where it is (`UpdateLanes`).
- It declines `NO_LANES` while its team has no lanes yet. The leader
  then waits `LANE_RETRY` and asks again (lanes come a few seconds into a
  round). It declines `TIMED_OUT` (the transaction's own) if it ran out of
  time, and the leader asks again.
- On commit, the mission goes to the squad's blackboard (the fire team's
  `mission`). The leader reads it from there, as members read the lane
  today.
- `War:Assign` stops assigning lanes every update. A squad's lane is its
  mission's way.

## 4. What the soldier port gains

Both are soldier-level, so they are NextSoldier's (`nextsoldier.soldier`):

- `LookAt(p, seconds)`: look at p a while, unless fighting (a NextBot
  soldier: `base_nextsoldier`'s `LookAt`; a bot player: its eyes, which
  steer nothing while it stands still).
- `Gesture(occasion)`: play a `nextsoldier.gestures` occasion (the
  controller's `Gesture`). The signals go through it.

`tests/fake_soldier.lua` records both.

## 5. Steps

Each step is a commit with its tests first, and keeps the suite green.

1. `wartactics.mission`: the factory, `Wait`, `Casualties`, `Progress`.
2. The port's `LookAt` and `Gesture`, in both soldiers and the fake.
3. `sv_missions.lua`: the request on the slow lane, its refusals, the
   mission on the squad. Its transaction is tested under LuaJIT with
   `list.schedule` on a fake clock (the transaction library is pure).
4. The leader's muster, ask and wait in `features.aiwar.orders`
   (`Objective`), with the scan and the forward signal. The members
   gather. Orders tests with the fake soldier.
5. Regrouping on casualties or no progress, to a hiding spot, and asking
   again.
6. Halt on a replaced mission.
7. On `pl_upward`: setup and the first waves, read as data (each squad's
   state and mission over time), and the tactics engine's tick cost before
   and after under `native/ws_profile`.

## 6. Later mission kinds

Each is a kind, its choice in the request, and its leading in the orders.
Each is secondary to the alpha squad (§3): never given to it, and given to
another squad only while the alpha squad is out on the objective.

- **Ambush** a room the enemy will come through: the squad hides at its
  doors and waits for contact. Needs rooms: the nav mesh's areas grouped
  into rooms (the seated stances' spawn rooms from the BSP are a start).
- **Assault** a room known to be heavily guarded: needs the team's
  sightings by room. Knowledge is earned (`aiwar-command.md` decision 6):
  only what soldiers saw, and when.
- **Topple a support base**: the enemy's turrets, dispensers and medics, as
  sighted. Needs the same reports.

## 7. Settled with the operator

1. A squad waits after spawning and after a regroup. After spawning, it
   waits for the next wave and the walk from spawn (`Wait`). After a
   regroup, it waits only for members still alive to reach the hiding
   spot, never for respawns.
2. Heavy casualties are half the mission's size: `CASUALTY_SHARE = 0.5`.
3. Members waiting with the leader take their battle stance (the crouch,
   `Pose`) and announce it, as in setup. The seated stances replace it
   once spawn rooms are known.
4. Special missions are always secondary to an alpha squad tending the
   objective directly (§3).
