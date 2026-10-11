# What belongs in foundation/: an admission rule

**Verdict.** Your intuition holds up, and it already has a name in the literature:
foundation should hold only Evans's *generic subdomains* and *cohesive mechanisms*,
and leave out the game modes that use them. The rule fails today because
`foundation/` admits code for being **pure** (no GMod globals), when it should admit
code for being **general** (no game mode in it). These are two separate questions.
`payload.lua` passes the first and fails the second. Keep the two axes apart, and
your examples become a rule you can test.

Scope: this answers *what is admitted*. Where moved files go, and in what order,
is a design question for the architect.

---

## 1. The rule

> A module belongs in `foundation/` only if all three hold. **(a) It is pure:** it
> uses no GMod globals and reaches I/O, time and entities through a port or plain
> values. **(b) It is mode-neutral:** it names no game mode, no feature, and no map
> entity that only one mode uses, so you could delete any one mode without editing
> it. **(c) It is shared:** at least two modes use it *today*, or it is a formalism
> whose policy callers supply (strategies, ports, data). Code that passes (a) but
> fails (b) or (c) is that feature's *model*. It stays pure and testable, but it
> lives with its feature. Dependencies point only *into* foundation, and inside it
> only downward through the categories below. Nothing in foundation may require
> `features.*`, `ws.*`, or a category above its own.

Test (b) is Evans's own wording for generic subdomains: *"Leave no trace of your
specialties in them."* Test (c) is Martin's Common Closure Principle: code that
changes for the same reason belongs in the same package. When payload changes,
the reason is payload, so the payload model changes together with its controller
and HUD.

### The closed set: four categories

There are four categories, listed bottom to top. Each may depend only on the ones
listed before it.

| # | Category | Admission test (one line) | Belongs here now |
|---|----------|---------------------------|------------------|
| 1 | **Structures** | It has a textbook or spec name and no game noun: a data structure, an algorithm, or a codec for a documented format. | KeyValues/UTF-16 reader (inside `localization`), `consolecfg` (cfg text to commands), CRC32/bit packing (inside `events`), graph search |
| 2 | **Formalisms** | It is a mechanism that runs a *policy* the caller plugs in, and it holds no rule of its own about any mode. | Round statechart (`rounds.lua` + `rounds/state`, with `Mode:Extend`), NextBot Action/Behavior engine (`npc.lua`), event registry and wire format (`events.lua`), feature loader (`features.lua`), Sandbox-vs-Gameplay mode (`gamemode.lua`) |
| 3 | **Gameplay types** | Every mode, or at least two, uses the same vocabulary of the game, and it names none of them. | `teams`, `players`, `combat`, `spawn`, `spectate`, `economy`, `loadout`, base `projectile`, `capture` (see §2) |
| 4 | **NS types** | It describes what a NextSoldier soldier perceives, decides or moves through, whichever mode hosts it. | `aiwar/{soldier,orders,tactics,squad,lanes,hearing,explore,hunt,track,posts,zone}`, `ns/*`, the NPC navigation parts NS uses (`npc/path`, `route`, `doors`, `portal`, `targeting`, `nav_gaps`) |

Categories 1 and 2 are what you called "standard structures and other necessary
formalities". Category 2 is Evans's *cohesive mechanism* almost word for word:
*"Partition a conceptually cohesive mechanism into a separate lightweight
framework. Particularly watch for formalisms."* It is also the *mechanism* half of
Hydra's policy/mechanism separation. The round statechart decides *how* a round
moves through its states. Which mode wins, and why, is *policy*, and policy
arrives as a `Mode` strategy. Harel's statecharts are the standard formalism for
this kind of hierarchical, event-driven state, so a statechart belongs in category
2. A particular soldier's chart belongs in 4, and a mode's chart belongs in its
feature.

### What fails the rule in today's tree

- **Mode strategies:** `rounds/{payload,koth,control_points,arena,destruction}`,
  `payload`, `payload/*`, `aiwar/scenario/*`
- **Holiday content:** `holiday/*`, `spells/*`, `hazards/pumpkin_bomb`, and the
  bosses `npc/{merasmus,headless_hatman,eyeball_boss,ghost,zombie,halloween_boss,boss_*}`
- **The AI-war mode itself:** `aiwar.lua` (roster, roles, respawn waves),
  `aiwar/{slots,spawns,overlay}`, `kill_feed`
- **Pure helpers for one ws module**, which are not game models:
  `scoreboard`, `nav_progress`, `admin_notices`, `settings`, `replicated`,
  `sound_paths`

The last group is a real gap in the closed set: pure, cross-cutting plumbing that
belongs to no mode and is no game concept. I recommend **not** opening a fifth
category for it, because that bucket would grow without limit. Each of these is a
pure helper for one `ws/` module and should sit next to it. The directory choice
is the architect's.

The dependency check confirms the direction problem is real today:
`aiwar/squad` requires `aiwar.slots` (the AI War panel), and `aiwar/orders`
requires `foundation.aiwar` (the war's roster). If both stay as they are, NS types
depend on a mode. On the healthy side, `rounds.lua` requires only `teams` and
`rounds.state`. The mode strategies extend it, and it does not know about them.
That is the shape the rule asks for.

---

## 2. Borderline cases

| Case | Verdict | Reasoning |
|------|---------|-----------|
| **Capture point shared by several modes** (`capture`, `capture/area`, `capture/master`, `capture/point_timer`) | **Admit: gameplay type** | TF2 builds cp, koth, payload checkpoints and arena all on `team_control_point`. Valve keeps `team_control_point.cpp` in the generic `game/server/`, outside `tf/`. Count consumers *by mode*, not by feature folder: only `features/capture` requires it, but that controller serves every mode. The cp *strategy* (`rounds/control_points`, `aiwar/scenario/control_points`) is not admitted. Watch for traces: a field named for payload's cart should be a generic objective. |
| **Economy** | **Admit: gameplay type** | Every player and team NPC holds an account, in every mode. It is a value type with one refusal (`InsufficientFunds`), and no mode owns it. If a later rule is mode-specific ("koth pays per tick held"), that rule lives in the koth feature and *calls* `economy`. |
| **Events** | **Split: the registry is a formalism; the definitions belong to their features** | `events.lua` is Source's `IGameEventManager` (typed schema, wire format, listeners, request rules): a mechanism with no policy. A definition such as "the cart reached checkpoint 2" is a payload fact, so the payload feature declares it. Only the small frozen *system* event set (see your v2 event kinds) may be declared in foundation. |
| **Teams** | **Admit: gameplay type, with a known TF2 bias** | Everything uses it (107 requires). Its team numbers, `HALLOWEEN = 5`, and its spawn-room tests come from TF2. That is acceptable until CS:S arrives. Then team *identity* (a gameplay type) and TF2's team *numbers* and rules (TF2 policy) may need to separate. Do not split it before then. |
| **Spectate** | **Admit: gameplay type** | Observer modes, death phases and target cycling apply in every mode. Its target descriptors carry `train` and `associatedTeam` for points. These are small traces of payload and cp, so keep them generic ("objective") rather than letting them multiply. |
| **Localization** | **Split: the codec is a structure; token lookup is glue** | The UTF-16 KeyValues reader is a codec for a documented format (category 1). Looking up `#Token` in the mounted TF2's files serves presentation, so it belongs with `ws/cl_localization.lua`. It is not a game concept. |
| **AI war: the war** (`aiwar.lua`: who fights for whom, roles, respawn waves, what the round permits) | **Reject: the aiwar feature's model** | This is a game mode ("a payload round fought by HL2 NPCs"). Your own note says AIWar is the mode and NextSoldier is the AI. The war uses NS. NS must not use the war. |
| **AI war: squads** (`aiwar/squad`) | **Admit: NS type, after one inversion** | Fire teams, leaders and spot claims are how a soldier coordinates in any mode. Today it requires `aiwar.slots` to read a slot's *pin*. The concept (LEADER/MEMBER) should be an NS value that the slot *carries*, so slots depend on squads and not the reverse. |
| **AI war: slots** (`aiwar/slots`) | **Reject: the aiwar feature's model** | Slots are the AI War panel's drafting list, sized by `mp_aiwar_team_size`: one mode's admin UI. |
| **AI war: scenarios** (`aiwar/scenario/*`) | **Reject: the aiwar feature's models** | Each one adapts NS to one round type (koth, payload, cp, arena). They are adapters between categories 3 and 4, specific to a mode by construction. |

The pattern across these cases: when a borderline module splits, the
**vocabulary or mechanism** is admitted and the **instance or policy** goes to the
feature.

---

## 3. Pitfalls of splitting this way, and how to keep the tests

1. **Losing headless tests by moving rules into controllers.** This is the main
   risk. "Out of foundation" must never mean "into `sv.lua`". A rejected model
   moves *as a pure file* into its feature folder. The harness already supports
   this: `T.require` loads any dotted path under `T.ROOT`, the gamemode folder
   (`tests/harness.lua` line 15). So `require("features.payload.model")` loads
   headless exactly as `foundation.payload` does now, and server-side `WS.require`
   resolves the same way (`ws/sh_core.lua` line 16). Make the move a pure refactor:
   change only the require path in the existing test, and keep every assertion.
   If any assertion has to change, the move changed behaviour.
2. **Client shipping.** `init.lua` sends foundation directories to clients with
   `AddCSLuaFile`, and the feature loader ships only `sh`/`cl` parts
   (`features.lua`, `CLIENT_PARTS`). A pure feature model the client needs (for
   example a HUD rule) will not reach the client unless something ships it. Check
   this before moving any model with a client consumer.
3. **Dependencies running the wrong way after the split.** See `squad`→`slots`
   and `orders`→`aiwar` above. Add the rule itself as a test: scan the
   `require("…")` strings of every file under `foundation/` and fail on
   `features.` or `ws.`, and on an upward category edge. It is cheap, it runs
   headless, and it stops the rule from eroding quietly. This is Martin's Stable
   Dependencies Principle turned into an executable check.
4. **Promoting code on a guess.** "CS:S will need it" is not a second consumer.
   Promote a model into foundation when a second mode actually requires it, and
   strip its mode names during the move. Promoting early produces an abstraction
   shaped by one mode, which costs more to change than duplicated code would.
5. **A kernel that is really TF2.** Gameplay types (rounds as
   `CTeamplayRoundBasedRules`, team numbers) are faithful to TF2. Valve's own
   split shows the cost: `teamplayroundbased_gamerules.cpp` sits in the generic
   `game/shared/`, while `team_train_watcher.cpp` (payload) and
   `team_control_point.cpp` sit in the generic `game/server/`, outside `tf/`. Valve
   put payload in its shared layer because several Valve mods shared it, and the
   generic layer filled up with TF-isms as a result. So engine practice does *not*
   by itself forbid payload in a shared layer. Your rule makes a different choice
   from Valve, and the justification is the Common Closure Principle, not Valve's
   precedent. Expect to revisit category 3 when a CS:S mode is a real consumer.
6. **Stable but concrete.** Martin's Stable Abstractions Principle says a stable
   package should be abstract. In this Lua code, "abstract" means ports and
   strategies (`Mode:Extend`, the soldier port, the loader's port). Foundation
   meets that for categories 2 and 4. Category 3 is concrete and stable. That is
   acceptable for values that rarely change, such as team numbers, but it is the
   place to look first if foundation starts changing for mode reasons.
7. **Lazy loading improves, it is not a cost.** Mode models that move into
   `features/<name>/` load only on maps whose entities ask for that feature. That
   supports the goal of keeping Lua memory low, instead of working against it.

---

## Sources

- Evans, *Domain-Driven Design Reference* (2015): "Generic Subdomains" ("Leave no
  trace of your specialties in them"), "Cohesive Mechanisms" ("Particularly watch
  for formalisms"), "Shared Kernel" ("Keep this kernel small").
  <https://domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf>
- Martin, *Agile Software Development: Principles, Patterns, and Practices* (2002)
  and *Clean Architecture* (2017), chs. 13–14: Common Closure, Stable
  Dependencies, and Stable Abstractions Principles. Summaries:
  <https://helix.sitecore.com/appendix/package-principles.html>,
  <https://blog.avenuecode.com/principles-of-package-and-component-design>
- Levin, Cohen, Corwin, Pollack, Wulf, "Policy/mechanism separation in Hydra,"
  SOSP 1975.
- Harel, "Statecharts: A visual formalism for complex systems," *Science of
  Computer Programming* 8 (1987): 231–274.
- Cockburn, "Hexagonal Architecture" (2005), on the ports that keep categories
  1–4 pure. <https://alistair.cockburn.us/hexagonal-architecture/>
- Gregory, *Game Engine Architecture*, 3rd ed. (2018), ch. 1: the "Gameplay
  Foundations" layer below "Game-Specific Subsystems".
- Epic, Gameplay Framework and GameMode/GameState: the engine supplies the
  formalism, and a game's subclass supplies the rules.
  <https://dev.epicgames.com/documentation/unreal-engine/gameplay-framework-in-unreal-engine>,
  <https://dev.epicgames.com/documentation/unreal-engine/game-mode-and-game-state-in-unreal-engine>
- Epic, Lyra: generic core plus Game Feature plugins per experience (ShooterCore,
  TopDownArena). This is the closest engine precedent for `features/<name>/`
  owning a mode. <https://dev.epicgames.com/documentation/unreal-engine/lyra-sample-game-in-unreal-engine>
- Valve, Source SDK 2013 tree (checked): `src/game/shared/teamplayroundbased_gamerules.cpp`,
  `src/game/shared/tf/tf_gamerules.cpp`, `src/game/server/team_train_watcher.cpp`,
  `src/game/server/team_control_point.cpp`. <https://github.com/ValveSoftware/source-sdk-2013>
- This repo: `foundation/` listing and headers; `require` graph of `foundation/aiwar`;
  `tests/harness.lua`; `ws/sh_core.lua`; `init.lua`.

---

## Amendment (phase 2 gate review, after 49d7d65)

1. **Clause (c), "shared", counts modules that require it, not modes served.**
   §2 admitted `capture` because one controller serves several modes. By that
   reasoning, any private helper of a controller that runs in every mode would
   also qualify; `rounds/spawn_doors` under `features/rounds` is the example.
   The tighter test: two or more modules outside the candidate's own family,
   in features or foundation, require it today. `rounds/spawn_doors` fails this
   test, so moving it to `features/rounds` is right. `capture` also fails it
   today: only `features/capture` and capture's own files require it. Revisit
   its place when a second dependent exists (for example the cp or aiwar
   scenarios reading capture's types). Until then, it is a candidate for
   `features/capture/`, not a settled gameplay type.
2. **`teams` in Formalisms is accepted as a label, not as a classification.**
   At file level there is no cycle: `rounds` → `teams` → `rounds/state`. The
   cycle appears only when categories are ranked whole, because `rounds` reads
   team vocabulary and one TF2 team rule (`Teams.ScrambleDue`). That means the
   round statechart still carries TF2 policy. Moving `teams` down a rank is
   the cheapest honest fix until the CS:S split separates team identity from
   TF2's team rules. The guard should say so where it places `teams`.

## Amendment 3 (phase 3 gate review, after 232521f)

1. **Reverse an inversion by moving the policy to its home. A port only hides
   it.** If a foundation module requires a mode because it *contains* that
   mode's policy, then injecting the policy (a function on the field, or a
   copied constant) empties the guard's exception list while the specialty
   stays inside foundation. That breaks clause (b) and only makes the guard
   look satisfied. Injection is right only when the dependency is on *data* the
   caller already owns, such as a snapshot value the controller can always
   fill. Moving vocabulary is right when the concept belongs lower down, for
   example a squad pin or a team's opponent.
2. **Clause (c): "family" means the module's own files, not its layer.**
   `ws/` glue modules count as dependents just as features do. A model that
   is always on and has no map entity (such as `loadout`) has `ws/` modules as
   its only consumers, and still qualifies when two or more distinct `ws/`
   modules need its vocabulary.

## Amendment 4 (after phase 3, fd2d3fb)

1. **NS types are admitted by the operator's decision, not by clause (c).**
   Today NextSoldier has one host, the AI war, so every NS module's dependents
   are in the aiwar family and clause (c) would admit none of them. The
   operator has decided that NS is a platform modes will host (TF2 and CS:S),
   and that is a product decision, outside what the rule settles. Clause (b)
   still applies with full force: an NS type names no mode.
2. **`aiwar/orders` (and its port, `aiwar/soldier`) fails (b), so it is aiwar's
   model, not an NS type.** Its header says it holds "the orders of an AI war
   soldier". Payload runs through the tree itself, not only through the
   doctrine table: the cart roles, `FollowCart`, `Sit`/`IsSeated`, and
   "riding the cart". The phase 3 review's "doctrine step" would generalise
   that tree for a second host that does not exist yet, which is promoting on
   a guess (pitfall 4). I withdraw it. The right step is to file orders as
   `PENDING → features/aiwar`. A mode-neutral NextSoldier tree becomes design
   work for the architect when a second mode really hosts NS soldiers.
