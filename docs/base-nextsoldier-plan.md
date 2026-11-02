# base_nextsoldier: NextSoldier's own NextBot base (issue #8 L1, L2)

**Status: implementation in progress.** `nextsoldier.base` and
`base_nextsoldier` are implemented. The remaining component and migration
work below is still planned.

The NextSoldier base replaces DrGBase for the gamemode's soldier entities.
The Halloween NPCs retain their `games.npc.nextbot` behavior through
`base_nextsoldier_npc`, which derives from `base_nextsoldier` and overrides
its incompatible lifecycle. `base_nextsoldier_combat` adds the combatant
port for those NPCs.

## 1. What we already have

- **`base_nextsoldier_npc`**: a GMod NextBot entity, the base of the
  Halloween NPC binding: a
  thin binding from GMod's NextBot to a `games.npc.nextbot` model. It
  implements an actor port with GMod's machinery, forwards the engine's
  events, and ticks the model's behaviour from `BehaveUpdate` (no
  coroutine). It inherits `base_nextsoldier` but keeps that model lifecycle.
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

The components are TF2's (server/NextBot/): the bot itself and its four
INextBotComponents, each updated every tick (`nextsoldier.base` is
organised so).

| Component (TF2) | Model | What it holds | Native (L2) |
|---|---|---|---|
| the bot (`INextBot`) | `nextsoldier.relations`, `nextsoldier.life` | alive, down, dead; damage and death; whom it fights: dispositions by entity, then faction, then default (`IsEnemy`, `IsFriend`) | yes: the relations table by entity and faction |
| `ILocomotion` | `nextsoldier.locomotion` | following a path (GMod's PathFollower, priced by the native calculator), facing, speeds; climbs, jumps, leaps, vaults and rappels as its own processes started by `ClimbUpToLedge`, `JumpAcrossGap`, `Jump` and carried out over ticks in its `Update` (the movement modules) | the path cost (done) |
| `IBody` | `nextsoldier.body` | posture (stand, crouch), head aim (`AimHeadTowards`, `IsHeadAimingOnTarget`), weapons held and the active one, animation | no |
| `IVision` | `nextsoldier.vision`, `.hearing` (exist) | seen, recognized, remembered (`GetPrimaryKnownThreat`), heard, ignored (`IsIgnored`) | yes: the sight checks over the soldiers |
| `IIntention` | `nextsoldier.intention` | the enemy, AI on or off, the queries; the behaviours (the chart's states, the war's) run from its `Update` | the enemy choice |

**No coroutine** (TF2 runs none per bot): DrGBase's `BehaveStart` becomes
the bot's `Reset`, and what yielded through `YieldCoroutine` (our leaps and
vaults) becomes a locomotion process ticked in its `Update`; what paused
(`PauseCoroutine`) becomes a behaviour that waits.

**Weapons** on TF2's split: the bot equips the best weapon for its threat
(`CTFBot::EquipBestWeaponForThreat`), the body aims, and the intention's
behaviours fire once the head is on target. Our own soldier weapons (L3)
come with the body.

**One class, its kind as data**, as `CTFBot` is one class whose player
class is data: `npc_nextsoldier`, each faction's soldier (Combine, rebel,
vortigaunt) a profile: model, weapons, posture, voice.

**Detouring the engine** (the operator, 2026-10-27: "feel free to use
detouring in the foundation lib if you need more power"): a component may
have the native foundation detour an engine function where Lua cannot reach
what it needs, as `docs/native-foundation-plan.md` ("Detouring the engine's
functions") assesses it: only against a hot path an engine profile names,
on the drop-in rule, patched in open and out in close, found by RTTI
descriptors rather than byte signatures. The likeliest uses are reading
`CNavArea` state natively for locomotion, and NextBot's own locomotion if
the bench shows it hot once DrGBase's Lua is gone.

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
6. **One class across**: `npc_nextsoldier` with the Combine profile behind
   a convar; the war fields it beside DrGBase's; the bench's A/B against
   DrGBase's, then the rebel and vortigaunt profiles.
7. **L2**: the relations table and the sight checks native, each measured.
8. **L4**: DrGBase leaves the server's mounts.

## 4. The operator's decisions (2026-10-27)

"Take tf2's organization in source-sdk-2013 over DrGBase for these design
decisions":
1. **The coroutine**: none; TF2's locomotion processes and behaviours that
   wait (§2).
2. **Weapons**: our own, on TF2's equip, aim and fire split, with the body
   (slice 5).
3. **The first class**: one class with profiles as data, as `CTFBot`; the
   Combine profile first (§3, slice 6).
