# NextSoldier's behaviours: the agent apart from the strategy (issue #8 S3)

**Status: decided otherwise (2026-10-27).** The operator: "lets have war
provide these behaviors to nextsoldier via the registry", "so war uses
nextsoldier and owns the behaviors", "as well as the squad monitor". The
behaviours stay the war's; NextSoldier owns the contract (the chart), the
soldier and a registry (`nextsoldier.behaviors`) through which the war
gives it its behaviours, compiled with the scenarios as the war starts, a
soldier's root being the registered `NextSoldier`. Built: the registry,
the war's fifteen behaviours registered (the monitors among them), roots
taken from it. §2's split is not done; §1 stands as the map of what the
war's behaviours read.

The operator's distinction (2026-10-27): NextSoldier concerns the agent
itself and runs on its own, without the tactics engine; the tactics engine
(`wartactics`) is the strategy that organises soldiers. NextSoldier's chart
(`nextsoldier.chart`, S2) is in place: every behaviour is one of its states.
What is left is where each behaviour lives, which today is all
`features/aiwar/orders.lua` (2,100 lines).

## 1. What each behaviour reads today

A script over `orders.lua`, each action class against the file's locals and
the soldier state's fields (`state.*`):

| Behaviour | Lines | Reads of the war |
|---|---|---|
| `Travel` | 308 | lanes (`Lanes`, `state.lane`, `laneIndex`, `onLane`, `laneDone`), squads (`Squad`), `state.war`, `state.member` |
| `Chase` | 41 | the leash (`Leashed`), `state.war`, `state.member`, `state.tactic` |
| `RetreatToCover` | 47 | the fire team's doctrine (`Tactics`), speech, `state.war`, `state.member`, `state.tactic` |
| `FindHealth` | 34 | the war's health kits (`Health`, `KitWorthIt`), speech, `state.war` |
| `CallMedic` | 11 | none: its own cooldown |
| `Humiliated`, `SeekAndDestroy` | 108 | the round's phase, the hunt board (`Hunt`) |
| `Objective`, `Idle` | 480 | jobs, squads, posts, carts, the cover claims |
| the monitors | 68 | the war's job allocation, the scenario, the squad's kind |

So no behaviour but `CallMedic` stands apart from the war today. Moving them
as they are would carry the war into NextSoldier.

## 2. The split

Each behaviour splits at one seam: **the agent does what it is told; the
strategy decides what to tell it.**

- **NextSoldier (agent):** behaviours that take plain goals and know only
  the soldier port and the soldier's own state:
  - `Travel(goal, gait, keep?)`: walk a route to a point, repath, unstick,
    hop, detour. No lanes: a lane becomes the waypoints the strategy hands
    it.
  - `Chase(enemy, leash)`: the leash is a value, not the war's rule.
  - `RetreatToCover(threat, radius)`: cover from the threat; whether to
    retreat is the strategy's.
  - `FindHealth(kit)`: walk to a kit it is given; which kit is worth it is
    the strategy's.
  - `CallMedic`, and the self-preservation monitor (the tactical one, minus
    the war's phases).
- **wartactics (strategy):** the monitors that hold the war's state
  (strategy, squad, scenario), the jobs and stages (`Objective` and its
  variants, `Idle`), lane walking (a lane is handed to `Travel` as
  waypoints), the doctrine's retreat and regroup decisions, health-kit
  choice, the hunt and humiliation.
- **The soldier's own state** (`nextsoldier.agent`, a model): what an agent
  behaviour may hold: hurt log, chase and retreat cooldowns, medic call. The
  war's state (`member`, `war`, `lane*`, `job`) moves to a wartactics state
  beside it, handed to strategy behaviours only.

The layer rule already enforces the direction: `wartactics` may require
`nextsoldier`, never the reverse (`tests/foundation_layers_test.lua`).

## 3. Slices

Each ships alone, tests first, live-checked on pl_upward (the bench map),
`check_lua.sh` and the bench's tick numbers held:

1. **`CallMedic`** to `nextsoldier/behaviours/` (it reads nothing of the war):
   the slice that sets the module layout and the agent state.
2. **`Chase`** with its leash as a value.
3. **`Travel`** split: the route-walking agent behaviour to NextSoldier;
   lane walking to `wartactics` as a strategy behaviour that feeds it
   waypoints. The largest slice; split again if it runs long.
4. **`RetreatToCover`, `FindHealth`**, their decisions to the strategy.
5. **The monitors, jobs, hunt and humiliation** to `wartactics`; what is
   left of `features/aiwar/orders.lua` is the war's wiring.

After slice 5, a soldier with only NextSoldier's behaviours (no
`wartactics`) can be stood up and driven by hand: the runtime half of "runs
without the tactics engine", which the layer test cannot show.

## 4. Questions for the operator

1. **Lanes as waypoints.** Today `Travel` walks a lane itself (index,
   on-lane, done). Moving that to the strategy, which hands `Travel`
   waypoints, changes who decides when a soldier leaves its lane. Agreed?
2. **Slice order.** Smallest first (`CallMedic`, `Chase`, then `Travel`),
   or `Travel` first, as it is where the most of the war is entangled?
