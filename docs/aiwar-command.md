# AI War: command, squads and monitors

The AI war's soldiers currently decide as individuals under a role table:
`foundation.aiwar` gives each soldier a role (the defense share, `Stance`,
`Rebalance`), `foundation.aiwar.orders` runs one `Objective` action per role,
and a fire team shares only a contact and a bound (`foundation.aiwar.tactics`).
This plan layers that into TF2's bot architecture, where a tactical monitor
contains a scenario monitor and a squad wraps the scenario's action. It adds
what TF2 lacks: a team that decides together.

`sdk/` below means `src/game/` of the Source SDK 2013 TF2 release.
Everything in `docs/pass2-contract.md` and the layers in
`docs/pass3-halloween.md` §0.1 still hold: models are pure `module(...)`
files under LuaJIT; controllers feed them; entities bind; views draw.

## 0. Decisions

1. **One Commander per team, outside the soldiers.** Team strategy is decided
   once, by a pure model, and not in N copies inside N soldiers that could
   disagree and over-commit (all of them deciding to block at once). A
   soldier's `StrategyMonitor` applies the Commander's decisions for that
   soldier and decides nothing itself. Precedent: TF2's `CTFBotSquad`
   (`sdk/server/tf/bot/tf_bot_squad.h`) is an event responder outside its
   bots, whose contained responders are its members.
2. **Self-preservation outranks the squad.** `TacticalMonitor` (retreat,
   unstuck, humiliation) contains the squad layer, as TF2's
   `CTFBotTacticalMonitor` contains `CTFBotScenarioMonitor`. A dying soldier
   leaves a bound, and its squad learns of it through an event. Squad
   discipline, such as holding under fire, is expressed from inside: the
   squad's actions answer `ShouldRetreat` with NO. It never overrides the
   monitor.
3. **The per-soldier tree:**

   ```
   NextSoldier(
     StrategyMonitor << TacticalMonitor(
       SquadMonitor << SquadLeader | SquadMember | Solo (
         ScenarioMonitor << PayloadAttacker | PayloadDefender (
           Push | Escort | Block | EstablishLine | Raid | Support ... ) ) ) )
   ```

   `A( B )` means A contains B for as long as A runs
   (`InitialContainedAction`). `A << B | C` means A decides which of B or C
   runs below it and replaces it when that changes (§5.3).
4. **Names follow TF2**, where a counterpart exists: `PayloadPush`,
   `PayloadGuard` and `PayloadBlock` (`sdk/server/tf/bot/behavior/scenario/payload/`),
   and `SquadMember` for `CTFBotEscortSquadLeader`. `PayloadEscort`, `Raid`
   and `Support` are Sandcastle's own.
5. **Collaboration uses five channels, and only these five** (§4):
   allocation (pulled down), commands (pushed down as events), reports (up),
   claims (sideways) and queries (between the engine and the stack). No
   action reads another soldier's action stack.
6. **Knowledge is earned.** The team's picture of the enemy comes only from
   its soldiers' reports: what they saw, and when. The Commander may read
   what a TF2 player's HUD shows (cart progress, checkpoints, timers,
   captures), and nothing more. No wallhacks by blackboard.
7. **DrGBase stays the body.** It aims, fires, reloads and animates. Its
   hooks are routed into the stack as events and queries (§6). Nothing in
   DrGBase is patched.
8. **Kit is not job.** A soldier's kit (shotgunner, crossbow, metrocop,
   hero) is what it is; its job (push, block, raid...) is what it does now.
   Today `role` is both. Allocation picks who fills a job by suitability,
   and kit is one factor (§2.3). This lands last (phase 6), because it
   changes the most.

## 1. The tree, level by level

| Level | TF2 counterpart | Owns | Reads | Handles (events) | Answers (queries) |
|---|---|---|---|---|---|
| `NextSoldier` | `CTFBotMainAction` | life and death | port | — | — |
| `StrategyMonitor` | — (new) | my job, my squad | Commander's allocation | `OnCommand*` from the Commander | — |
| `TacticalMonitor` | `CTFBotTacticalMonitor` | survival: humiliation, retreat to cover | my health, threats, round state | `OnInjured`, `OnSight`, `OnOtherKilled` | `ShouldRetreat` (default rule) |
| `SquadMonitor` | squad branch of `CTFBotScenarioMonitor::InitialContainedAction` | leader, member or solo | squad roster | squad formed, disbanded, leader lost | — |
| `SquadLeader` | — | the squad's intent: where it goes, bound or flank, target | squad blackboard, job | reports from members | `ShouldAttack` (squad's target first) |
| `SquadMember` | `CTFBotEscortSquadLeader` | keeping formation or element on the leader's intent | leader's intent, claims | leader's orders | `ShouldRetreat` = NO while its element holds |
| `ScenarioMonitor` | `CTFBotScenarioMonitor` | the side action | my side (the doctrine's `Side`), field | — | — |
| Side actions | — (new) | `PayloadAttacker`, `PayloadDefender` (`ControlPointAttacker`, `ControlPointDefender` on points): runs my job, and changes itself when my side does | my job, field | — | — |
| Job actions | `CTFBotPayloadPush`... | doing the job | field, squad intent | job-specific | `ShouldHurry` (rushers), `ShouldAttack` |

Each level is a `foundation.npc` Action. Engine features are in §5.

### 1.1 StrategyMonitor

Its whole job is to turn the Commander's allocation into this soldier's
`desiredJob` and `desiredSquad`, at safe moments:

- A job change waits until the soldier is between bounds, or out of
  contact, or has waited `HANDOFF_WAIT` (4 s). A CRITICAL command skips the
  wait.
- A soldier keeps a job for at least `MIN_TENURE` (15 s) unless the change
  comes from a CRITICAL command. This damps oscillation per soldier; the
  Commander damps it per team (§2.2).
(Round won or lost is the tactical monitor's, as in TF2: §1.2.)

### 1.2 TacticalMonitor

Self-preservation lives here, as it does in TF2
(`CTFBotTacticalMonitor::Update`):

- **Round lost:** the losers `SuspendFor` `Humiliated`. Their orders are
  dropped, they answer `ShouldAttack` NO and `ShouldHurry` YES, and DrGBase
  keeps them away from what they fear. This is built (phase 2).
- **Retreat:** when `ShouldRetreat` from the stack is not NO, and health is
  under `RETREAT_HEALTH`, suspend for `RetreatToCover`: the port's
  `CoverSpot` away from the threat, held until healed or `RETREAT_TIME`
  passes. Not built yet.

A monitor's `SuspendFor` buries the monitor itself and everything under
it, as TF2's `SuspendFor( new CTFBotRetreatToCover )` does. The squad and
the job resume when the suspension is over.

Getting unstuck is **not** the tactical monitor's. In TF2 it belongs to the
moving actions and `CTFBotMainAction::OnStuck`, and here it stays in
`Travel` (sidestep, reroute, hop). The door watchdog stays in the port.

### 1.3 SquadMonitor, SquadLeader, SquadMember

A squad is today's fire team, promoted to an object (§3). `SquadMonitor`
runs `SquadLeader` if I am the squad's leader, `SquadMember` if I am in a
squad, and `Solo` otherwise. Each of them contains the `ScenarioMonitor`, so
leader and members all run their job. They differ in who sets the intent:

- **The leader** runs the job and publishes the squad's intent on the squad
  blackboard: a move point, a mode (`advance`, `bound`, `flank`, `hold`,
  `fall back`) and a focus target.
- **A member** runs the same job, but it takes its destination from the
  intent: its element's bound spot, its place in formation, or a cover spot
  near the leader's hold point. It answers `ShouldAttack` with the squad's
  focus target first.

Bounding overwatch, flanking and falling back (`foundation.aiwar.tactics`)
become the leader's modes. The bound swap stays squad state.

## 2. The team layer: Commander

`foundation.aiwar.command`: one `Commander` per team, a pure model run by
the aiwar controller at `COMMAND_INTERVAL` (1 s).

### 2.1 Situation

Signals, each with how the Commander gets it:

| Signal | Source |
|---|---|
| cart progress, speed, close, contested | watcher and track (HUD-equivalent) |
| checkpoint captured, time left | round and timer controllers (HUD-equivalent) |
| line integrity: share of posts manned, losses near the line in the last 20 s | own soldiers' reports |
| enemy strength near each cart | reports: sightings decayed over `SIGHTING_MEMORY` (8 s) |
| raiders behind our line | reports of enemy seen behind our posts |
| casualty rate, per team | kills seen (`OnOtherKilled`) |

`Situation` is a plain table, rebuilt each command tick from the
controller's field and the team blackboard. It holds no engine handles.

### 2.2 Allocation

The output is a demand per job: `push`, `escort`, `guard` (today's defend),
`block`, `raid`, `support`, and later `assault` for control points. Each
job's demand is a utility of the situation. The current defense share
becomes two of those utilities: cart threat for `guard` and `block`, own
push for `push` and `escort`. So today's behaviour is the first version of
the scoring, not something to throw away.

- **Damping:** demands are quantised to tenths. A change is applied only if
  it holds for `ALLOCATION_HOLD` (3 s), or at once for a CRITICAL signal
  (checkpoint about to fall, line collapsed).
- **Moves:** as today, the fewest soldiers move. The difference is who
  moves: the most suitable, not the newest. Suitability = distance to the
  job's area, kit fit, not in contact, and tenure past `MIN_TENURE`. Whole
  squads move when one squad's size matches the change.

### 2.3 Commands

The Commander can also push intents that no allocation expresses. They are
delivered as NextBot command events (`sdk/server/NextBot/NextBotEventResponderInterface.h`):

| Command | Event | Example |
|---|---|---|
| surge | `OnCommandApproach(pos)` to a squad | all blockers to the cart: checkpoint about to fall |
| regroup | `OnCommandApproach(pos)` | squad losses over half: meet at the line |
| fall back | `OnCommandRetreat(threat, range)` | line collapsed |
| focus | `OnCommandAttack(target)` | a hero or turret reported, several squads nearby |
| hold | `OnCommandPause(duration)` | setup, cart stopped: hold posts |

A command is an event, so each level may take it at the priority it
chooses. `TacticalMonitor` ignores a surge while its soldier is retreating
at 10% health. That is the NextBot property worth keeping: commands steer,
they do not puppet.

## 3. The squad layer

`foundation.aiwar.squad`: today's fire team (`War.fireTeams`, contact,
bound) becomes a `Squad` with:

- **Members and a leader.** The leader is elected by tenure, then health.
  On the leader's death, the next is elected, and `OnSquadLeaderChanged` is
  sent to every member.
- **An event responder over its members**, as `CTFBotSquad` is.
  `squad:Event(name, ...)` delivers to each member's stack. Commands from
  the Commander reach squads this way.
- **A blackboard:** contact (as now), intent (§1.3), bound state (as now)
  and claims (§4).
- **Membership by job, as now.** A job change moves a soldier to a squad of
  the new job; whole-squad moves (§2.2) keep squads together.

## 4. Collaboration channels

| Channel | Direction | Carrier | Examples |
|---|---|---|---|
| Allocation | team → soldier (pulled) | Commander's allocation, applied by `StrategyMonitor` | job and squad assignment |
| Commands | team → squad → soldier (pushed) | `OnCommand*` events with priority | surge, regroup, fall back, focus, hold |
| Reports | soldier → squad → team | `Report(kind, pos, time, subject)` on the blackboards | sighting, under fire, line broken, cart blocked, need support |
| Claims | soldier ↔ soldier | `Claim(kind, key, holder, expires)` on a blackboard | cover spots, posts, ring slots, flank side, a target's attacker count |
| Queries | engine ↔ stack | `Behavior:Query(name, ...)` (§5.1) | should attack, should hurry, should retreat, more dangerous threat |

Claims replace today's slot arithmetic: `Ring(slot)`, `posts[slot + 1]` and
`CoverSpot`'s `exclude`. The rule is first come, first served, with expiry,
and a soldier that dies releases what it held.

Reports are the only way enemy knowledge enters a blackboard (§0.6).

## 5. Engine additions (foundation.npc)

1. **Queries.** `Behavior:Query(name, ...)` follows NextBot's contextual
   query walk (`sdk/server/NextBot/NextBotBehavior.h`):
   - start at the innermost active child;
   - ask it, then the actions buried under it;
   - then move to the containing parent and repeat;
   - the first answer other than `ANSWER_UNDEFINED` wins.

   Answers are `ANSWER_NO`, `ANSWER_YES` and `ANSWER_UNDEFINED`. For
   `SelectMoreDangerousThreat`, the first action that returns a threat wins.
2. **Event groups.** A `Group` responder holding Npcs, so an event sent to a
   Squad reaches each member (§3).
3. **Replacing a child.** The engine has no "parent replaces child" (and
   neither has NextBot): a child changes itself. The pattern, as
   `Objective` already uses for roles:
   - a monitor writes `state.desired<Level>`;
   - the child's base class checks it at the top of `Update`, and
     `ChangeTo`s the desired action when it differs and the handoff rule
     allows (§1.1).

   It lives in one base class per level (`Job`, `SquadRole`), not in each
   action.

## 6. The DrGBase bridge

`ws_drg_soldier` forwards DrGBase's hooks to the controller, which
forwards them to the soldier's stack. Each hook below is in DrGBase's source
with the arguments shown (`entities/drgbase_nextbot/ai.lua`, `awareness.lua`,
`hooks.lua`):

| DrGBase hook | Stack | Notes |
|---|---|---|
| `OnInjured(dmg)` | event `OnInjured` | replaces `EntityTakeDamage` → `hurtAt` |
| (death) | event `OnOtherKilled` to the victim's squad and nearby soldiers | from the controller's `Discharge` (entity removed), not `OnKilled`: that is DrGBase's own death routine, and overriding it would break dying |
| `OnSpotted(ent)` / `OnLost(ent)` | events `OnSight` / `OnLostSight`, and a sighting report | feeds §2.1 |
| `OnNewEnemy(ent)` / `OnLastEnemy(ent)` | events `OnContact` / `OnContactLost` | contact starts and ends |
| `OnNavAreaChanged` | event | TF2 uses it in the tactical monitor |
| `OnFetchEnemy(a, b)` → bool (a is preferred) | query `SelectMoreDangerousThreat` | squad focus fire; `nil` leaves DrGBase's priority-then-range order |
| `OnRangeAttack` / `OnMeleeAttack` | query `ShouldAttack` (NO → return true to hold fire) | replaces the `WSDisarmed` special case |
| `ShouldRun` | query `ShouldHurry` | replaces `WSRun` |

Steering (`NSTarget` and `FollowPath`) stays as it is. Only where the
target comes from changes.

## 7. From today's code

| Today | Becomes |
|---|---|
| `War:Assign`, `Stance`, `DefenseShare`, `Rebalance` | `Commander` allocation (§2.2); `DefenseShare` survives as two utilities |
| role = kit + job | kit and job separate (phase 6) |
| fire team `{ contact, bound, flank }` | `Squad` with blackboard, leader and intent |
| `Objective` per role | job actions under `ScenarioMonitor` |
| `Objective:Fight`, `Attack`, `Defend` | squad modes (leader) and element roles (member) |
| `Travel` stuck ladder, door watchdog | unchanged: moving actions and the port (as in TF2) |
| `Controller:Disarm` and humiliation | `TacticalMonitor` → `Humiliated` (answers `ShouldAttack` NO) |
| slot arithmetic for spots | claims |
| `Controller:Equip` kits | kit assignment by the Commander's suitability (phase 6) |

## 8. Phases

Each phase ships on its own and keeps the suite green.

1. **Queries, groups and the DrGBase bridge** (§5.1, §5.2, §6). Behaviour
   stays as it is, except that attack and run go through queries. Tests:
   the query walk order against NextBot's (innermost first, buried, then
   parent); every hook in §6 reaching the stack.
2. **The tree with today's behaviour.** Insert `StrategyMonitor`,
   `TacticalMonitor` (with `Humiliated`), `SquadMonitor` (Solo only) and
   `ScenarioMonitor`. The orders tests must pass unchanged apart from
   action names in `Describe`.
3. **Squads.** Built as:
   - leader election (heroes, then the oldest, sticky) and
     `SquadLeader`, `SquadMember` or `Solo` under `SquadMonitor`;
   - members regroup on a far leader in a fight, bound on the leader's line
     (spread by place), and fight the leader's enemy
     (`SelectMoreDangerousThreat`);
   - cover spots are claimed.

   Not yet:
   - a published leader intent with modes: bounding and flanking are still
     the fire team's shared state, which works without one;
   - claims for posts and ring slots: role slots already keep those
     exclusive within a role.
4. **Reports and Situation.** Sightings, line integrity and casualty rates
   on the blackboards. Tests: decay, and no enemy fact without a report.
5. **Commander.** Allocation by utility, damping and suitability-based
   moves; commands as events. Tests: race scenarios reproduce today's
   defense share first, then the new signals (line collapse → guard
   surge).
6. **Kit and job separated.** Kits assigned by the Commander; any kit can
   do any job, and fit is scored.
7. **Later jobs:** `assault` and `hold` for control points, medic and
   spotting support. Each is a job action plus a utility, with nothing new
   in the tree.

## 9. The case against

- **It is a lot of machinery for 8 to 16 soldiers.** TF2 ships bots without
  a commander, and players find them passable. The answer: phases 1 to 3
  pay off on their own (queries fix soldiers fighting their orders; squads
  fix bounding that is only simulated). Phases 4 and 5 are where the risk
  is, and they stay optional until 1 to 3 have been played.
- **Utilities oscillate.** A scored allocator with noisy inputs will
  thrash. Damping is designed in (§1.1, §2.2), but the constants can only be
  found in play. The overlay must show each job's demand and why it
  changed.
- **Reports make the team slower than the truth.** That is on purpose
  (§0.6), and it means a team can be surprised. If it feels dumb rather
  than fair, shorten `SIGHTING_MEMORY` or add spotting (a support job), not
  omniscience.
- **Performance.** At 16 soldiers the queries (a few per soldier per tick,
  each a walk of about 6 actions) are cheap. The Commander at 1 Hz is
  cheap. Claims are hash lookups. What to watch is `CoverSpot`
  (`navmesh.Find` plus traces), which claims should call less often, not
  more.
- **DrGBase's own brain still runs underneath.** Where it ignores a hook
  answer, that shows up as a soldier doing its own thing. §6 lists only
  hooks confirmed in its source. How DrGBase behaves when a hook returns
  mid-action is untested.

## 10. Settled after review

1. **Heroes lead.** A hero (Alyx, Barney) in a squad is always its leader;
   election by tenure then health applies only to squads without one.
2. **Players count, discounted.** The Commander counts a teammate player
   near a cart as half a soldier of friendly strength: their positions are
   what a teammate's HUD shows, but they follow no plan.
3. **Commands are voiced and shown.** The squad leader who receives a
   command speaks an HL2 line for it (Combine radio chatter, rebel shouts)
   and shows it as a chat bubble above its head for a few seconds (a
   client view of a networked "said" event). Chat lines are for admins with
   the soldier overlay on.

## 11. Scenarios

The war is no longer payload only. What it fights over is a Strategy,
`foundation.aiwar.scenario`, picked from the rounds mode's `NAME`
(`payload`, `control_points`, `koth`), never from the map. A map with no
such mode refuses `mp_aiwar_start`. Each variant briefs the field (its
doctrine of jobs and its objectives) and allocates each team's stance once
per controller think: the first slice of the Commander in §2, with §2.2's
damping for the point scenarios. A won round is the `humiliation` phase, in
which the winners hunt the losers until the next round.

The design, its TF2 sources, the field the controller builds and the work
packages are in `docs/aiwar-koth-cp.md`.
