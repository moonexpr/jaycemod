# base_nextsoldier: NextSoldier's own NextBot base (issue #8 L1, L2)

**Status: plan, for the operator's approval. Nothing below is built.**

The soldiers run on DrGBase today, and after foundation went native its
think is most of the Lua left on the server thread (the bench: its
per-entity think 19 to 23 %, enemy handling 9 to 10 %, path following 7 to
8 %). DrGBase is to go entirely; NextSoldier keeps only its interface
(`nextsoldier.base`, L0), implemented from scratch with high-level models,
native where that pays. The soldiers' classes are DrGBase's until the new
base passes the same contract and the bench.

## 1. What we already have

- **`ws_nextbot`**: our own GMod NextBot entity, the base of the bosses: a
  thin binding from GMod's NextBot to a `games.npc.nextbot` model. It
  implements an actor port with GMod's machinery, forwards the engine's
  events, and ticks the model's behaviour from `BehaveUpdate` (no
  coroutine). The pattern `base_nextsoldier` follows.
- **The contract**: `nextsoldier.base` (seven components, the methods
  required and the posture optional), the in-game check
  `ns_base_contract`, and `drg_interface.py check`.
- **Models a component stands on**: `nextsoldier.vision` and `.hearing`
  (the senses, TF2's IVision), the movement modules (`leap`, `rappel`,
  `noise`, `detour`, `doors`, `portal`), `wetsands.navsearch.Calculator`
  (the path cost, native), `list.schedule` (cooperative tasks in a time
  slice), `generator.state_machine` and `generator.hfsm`.

## 2. The design

`base_nextsoldier` (an entity, `base_` by GMod's convention) is a
composition root and nothing more: it builds one model per component of
`nextsoldier.base`, wires each to GMod's NextBot through a port, and
implements the contract's methods by delegating to them. The models are
pure Lua over ports, tested under LuaJIT, each with a native twin where the
bench says it pays (L2).

| Component | Model | What it holds | Native (L2) |
|---|---|---|---|
| relations | `nextsoldier.relations` | dispositions by entity, then faction, then default; priorities | yes: a table by entity and faction, asked per sight check |
| senses | `nextsoldier.vision`, `.hearing` (exist) | seen, recognized, remembered; heard | yes: the sight checks over the soldiers |
| intention | `nextsoldier.intention` | the enemy (chosen from the senses by relations and priority), AI on or off, the stage of fighting it (idle, new, chase, avoid, range or melee attack) as a state machine raising the `On*Enemy` hooks | the enemy choice |
| locomotion | `nextsoldier.locomotion` | following a path (GMod's PathFollower, priced by the native calculator), facing, jumping, climbing and dropping (the movement modules), speeds | the path cost (done) |
| posture | in locomotion | crouching, where the class has it | no |
| body | `nextsoldier.body` | weapons held, the active one, aim and shoot position, animations | no |
| life | `nextsoldier.life` | alive, down, dead; damage and death | no |

The behaviour coroutine DrGBase's interface exposes (`BehaveStart`,
`YieldCoroutine`, `PauseCoroutine`; our leaps and vaults yield through it)
becomes a `list.schedule` task per soldier, run in a time slice from
`BehaveUpdate`, so the names are kept and no Lua coroutine runs per entity
unless a task needs one.

## 3. Slices

Each ships alone, tests first; nothing switches a soldier until the last.

1. **The skeleton**: `base_nextsoldier` on GMod's NextBot, every required
   method present and delegating to stub models; `ns_base_contract`
   checks it beside DrGBase's classes.
2. **Relations**: `nextsoldier.relations` and the war's relations
   (`features/aiwar/sv_relations.lua`) on it.
3. **Intention**: the enemy and the stages of fighting it, on the senses
   and relations.
4. **Locomotion and posture**: path following on the native calculator,
   the movement modules wired as DrGBase's hooks are today.
5. **Body and life**: weapons held and fired (with L3: our own soldier
   weapons in place of DrGBase's), animation, damage and death.
6. **One class across**: a test class, `npc_nextsoldier_combine`, on the
   new base behind a convar; the war fields it beside DrGBase's; the
   bench's A/B (`--legs native:npc,...` with the new class) against
   DrGBase's, then each class.
7. **L2**: the relations table and the sight checks native, each measured.
8. **L4**: DrGBase leaves the server's mounts.

## 4. Questions for the operator

1. **The coroutine.** Keep `YieldCoroutine`/`PauseCoroutine` as names over a
   `list.schedule` task (no per-entity Lua coroutine), or drop them from
   the interface and rewrite the leaps and vaults as steps of a behaviour?
2. **Weapons.** DrGBase's soldiers hold `drgbase_weapon` SWEPs. Build our
   own soldier weapons (L3) inside slice 5, or first keep firing through
   GMod's NPC weapon path?
3. **The first class across.** The Combine soldier (the most fielded), or
   the vortigaunt (the simplest: no weapons, no posture)?
