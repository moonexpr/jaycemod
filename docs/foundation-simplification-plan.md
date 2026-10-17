# Keeping foundation/ foundational: plan

Status: proposed. Written 2026-10-10 by the architect, reconciled with
`docs/research/foundation-admission-rule.md` (the scholar's verdict).
Phase 1 (§7) can be carried out as written. Every later phase has a gate.

## 0. Summary

`foundation/` has 131 modules and 24,188 lines. It mixes general formalisms,
like the round statechart and the NextBot Behavior engine, with one mode's
rules: payload, spells, Halloween bosses, and the AI war itself.

The plan adopts the scholar's admission rule. A module stays in foundation only
if it is all three:

- **pure**: no engine; I/O, time and entities reach it through a port;
- **mode-neutral**: it names no mode, feature, or entity only one mode uses;
- **shared**: two or more modes use it today, or it is a formalism whose
  policy the caller plugs in.

Each module that stays goes into one of four closed categories.

Under that rule, **54 modules (10,336 lines) stay** and **77 modules (13,852
lines) move**. A moved module goes to the feature, or the `ws/` module, it
serves. It moves **as a pure file**, not into `sv.lua`, so every headless test
keeps running unchanged apart from its `require` path.

Phase 1 sets up the rest:

1. a guard test that enforces the rule;
2. one shared structure (`foundation.geometry`), which deletes 8 copies of
   `Distance`;
3. four server-only feature models moved out of foundation.

It touches none of the uncommitted work in the tree.

Baseline, measured 2026-10-10 by running the commands:

- `.devtools/bin/check_lua.sh` prints `compiled 455 files` and
  `TOTAL 1805 passed, 0 failed`.
- `.devtools/bin/run_lua_tests.sh` runs 123 test files.

---

## 1. Survey (measured by script, not by eye)

The scripts parsed every `foundation/**/*.lua`. They counted `X.__index = X`
classes, metatables thrown through `error(setmetatable(...))`, and `error(`
calls. They also counted the test files whose `T.require("foundation.<m>")`
loads each module, and the require edges in and out of foundation.

### 1.1 Custom types

- **Classes:** 42 of 131 modules define metatable classes, 61 `__index` sites
  in all. The class-heavy ones are `npc.lua` with 7, then `rounds.lua`,
  `spells.lua`, `holiday/wheel.lua`, `npc/debug.lua` and `loadout.lua` with 3
  each.
- **Named error types:** only two modules raise them:
  - `loadout.lua:65-94`: six refusal metatables plus a `Refused` predicate.
  - `economy.lua:14-18`: `InsufficientFunds`.
- **String-kind errors:** `events.lua:32-37,68-81` already uses
  `{ kind, message }`.

Ranked by type cost against what the types buy:

| Module | Lines | Classes | Error types | Methods | Test files / cases | Verdict |
|---|---|---|---|---|---|---|
| loadout | 282 | 2 (+refusal factory) | 6 | 11 | 1 / 20 | Highest cost. Six metatables to tell player refusals from bugs. Identity-based (see §9). |
| economy | 80 | 1 | 1 | 7 | 1 / 9 | A class and an error type for an 80-line ledger. |
| holiday/wheel | 620 | 3 | 0 | 31 | 1 / 21 | Many types, one test file. Moves to a feature anyway. |
| spells | 288 | 3 | 0 | 25 | 3 / 49 | Moves to a feature anyway. |
| npc/debug | 815 | 3 | 0 | 14 | 4 / 183 | Debug tooling. Moves. |
| npc | 605 | 7 | 0 | 76 | 13 / 413 | **Keep.** This is the Behavior statechart, and its types *are* the formalism. |
| rounds | 1163 | 3 | 0 | 58 | 16 / 322 | **Keep.** The round statechart. |
| events | 515 | 1 (+TypeMeta) | string kinds | 11 | 1 / 27 | **Keep.** Typed wire schema; the types buy network safety. |

The conclusion: the custom types cost the most where they sit on mode content
or small ledgers. Where they *are* a formalism, they pay for themselves.
Reducing types is a side effect of the moves (§3) plus phase 3's ledger and
refusal cleanup. It is not a goal on its own.

### 1.2 Re-implemented helpers

`local function Distance(a, b)` is byte-identical, with `z` defaulting to 0,
in eight places:

- `aiwar/lanes.lua:49`
- `aiwar/tactics.lua:33`
- `aiwar/hunt.lua:29`
- `aiwar/explore.lua:33`
- `aiwar/scenario/freeform.lua:29`
- `aiwar/scenario/control_points.lua:74`
- `ns/inspect.lua:23`
- `aiwar/track.lua:7`, exported, with `z` required

`nodegraph.lua:42` is a ninth copy with `z` required. `Nearest` has six
variants, but they differ, so leave them.

### 1.3 Dependency direction (measured)

Once the §3 mapping is applied, there are three wrong-way edges:

| Edge | Why it is wrong | What it uses |
|---|---|---|
| `aiwar/orders.lua:66` (NS) requires `foundation.aiwar` (moves to a feature) | NS uses the war | `BLOCK DEFEND ESCORT EXPLORE MEDIC PUSH RAID SUPPORT`, `EnemyOf`, `DefenseShare` |
| `aiwar/squad.lua:11` (NS) requires `foundation.aiwar.slots` (moves) | NS uses the panel | `LEADER`, `MEMBER` |
| `rounds.lua` requires `teams`, and `teams` requires `rounds.state` | A cycle across the scholar's order: formalisms 2, gameplay 3 | Rounds uses `RED BLUE SPECTATOR UNASSIGNED FIRST_GAME_TEAM ScrambleDue`. Teams uses `STATE.TEAM_WIN/STALEMATE/GAME_OVER`. |

The third edge is fixed by classification, not by code. See §2.

Event *definitions* already live outside foundation, in `features/*/sh.lua`
and `ws/sh_*.lua`; `events.lua` holds none. The scholar's "definitions go to
their features" is therefore already true.

---

## 2. Taxonomy: four closed categories, bottom-up

This adopts the scholar's four categories, with one adjustment. A category may
depend only on itself and the categories above it in this list.

| # | Category | Admission test (one line) |
|---|---|---|
| 1 | **Structures** | It has a textbook or spec name and no game noun: a data structure, an algorithm, or a codec for a documented format. |
| 2 | **Formalisms** | A mechanism that runs a policy the caller plugs in (a Strategy, a port, data), and holds no rule of its own about any mode. |
| 3 | **Gameplay types** | At least two modes use the same game vocabulary today, and it names none of them. |
| 4 | **NS types** | It describes what a NextSoldier soldier perceives, decides or moves through, whichever mode hosts it. |

There is no fifth bucket. Pure plumbing that serves one `ws/` module goes next
to that module (§3.3).

**Adjustment (judgment call): `teams` is a formalism, not a gameplay type.**
The round statechart needs to know who plays the round, and `teams` needs to
know how a round ends. Both are verified in §1.3. With teams in category 3 the
order has a cycle (categories are ranked whole; see the admission rule's
Amendment 2 for the real reason: `rounds` reads `Teams.ScrambleDue`). Treating the team set as the
round's participants, inside the round formalism, removes the cycle with zero
code change. The scholar's note on TF2 bias still applies: split team identity
from TF2's team numbers when a CS:S mode becomes a real consumer.

**The admission rule, from the scholar:** a module that is pure but fails
"mode-neutral" or "shared" is its feature's *model*. It stays pure and lives in
`features/<name>/`. Dependencies point only into foundation, and within it only
downward through the categories.

---

## 3. Every module mapped

This mapping was produced by a script (it covers all 131 modules, with none
unmapped or doubly mapped). The guard test in phase 1 encodes it.

### 3.1 Stays in foundation (54 modules, plus `geometry` added in phase 1)

- **1 Structures (3):**
  - `npc/route`: A* with a binary heap.
  - `consolecfg`: a cfg-text codec.
  - `geometry`: new.
  - Later, the KeyValues reader split out of `localization` (§8, phase 6).
- **2 Formalisms (9):**
  - `rounds`, `rounds/state`, `teams`: the round statechart and its
    participants.
  - `npc`, `npc/actor`, `npc/combatant`: the Behavior engine and its ports.
  - `events`: the event registry and wire schema.
  - `features`: the feature loader.
  - `gamemode`: the Sandbox/Gameplay machine.
- **3 Gameplay types (21):**
  - `players`, `players/attributes`, `spawn`, `spectate`, `economy`, `loadout`
  - `combat`, `combat/weapon_mimic`, `combat/weapon_slot_filter`
  - `projectile`, `projectile/{rocket,grenade,pipe,jar}`
  - `capture`, `capture/{area,master,point_timer}`: shared by cp, koth,
    payload and arena, as the scholar's §2 argues.
  - `rounds/timer`, `rounds/limits`
  - `npc/targeting`: who may hurt and see whom. Bosses, Jarate and the combat
    NextBot all use it.
- **4 NS types (22):**
  - `aiwar/{tactics,squad,lanes,hearing,explore,hunt,track,posts,zone}`
    (`aiwar/{soldier,orders}` move with phase 5: the admission rule's Amendment 4)
  - `ns/tuning`
  - `npc/path`, `npc/path/{ground,hl2,scatter,tfbot}`
  - `npc/{doors,portal,brushes,clip}`, `nav_gaps`: the navigation that NS
    moves through.
  - Judgment call: `brushes` and `clip` are not in the scholar's list. They are
    the same kind of nav-blocker rule as `doors`, so they join it.

### 3.2 Moves to a feature, as pure model files (67 modules)

| Destination | Modules | Client needs it? |
|---|---|---|
| `features/gamemode` | `gameplay` | no (**phase 1**) |
| `features/holiday` | `holiday/on_holiday` | no (**phase 1**) |
| `features/holiday` | `holiday`, `holiday/{fortune,gift,halloween}` | `holiday`, `gift`: yes |
| `features/boss_timer` | `npc/boss_timer` | no (**phase 1**) |
| `features/tag` | `npc/tag` | no (**phase 1**) |
| `features/wheel` | `holiday/wheel` | yes |
| `features/payload` | `payload`, `payload/{hud,race}`, `rounds/payload` | yes, except `rounds/payload` |
| `features/koth` | `rounds/koth` | no |
| `features/arena` | `rounds/arena` | yes |
| `features/rounds` | `rounds/{control_points,destruction,spawn_doors,text}` | all but `spawn_doors` |
| `features/capture` | `capture/hud` | yes |
| `features/spells` | `spells`, `spells/*` (14), `projectile/orb` | `spells`, `halloween`, `caster`: yes |
| `features/hazards` | `hazards`, `hazards/*` (5) | `hazards`, `pumpkin_bomb`: yes |
| `features/haunting` | `npc/{merasmus,eyeball_boss,headless_hatman,halloween_boss,ghost,zombie,hover}` | five of seven: yes |
| `features/npc` | `npc/{profile,spawner}` | no |
| `features/npc` | `npc/boss_events` | yes |
| `features/nbdebug` | `npc/debug`, `aiwar/overlay`, `ns/overlay` | yes |
| `features/aiwar` | `aiwar`, `aiwar/{slots,spawns}`, `aiwar/scenario`, `aiwar/scenario/*` (5), `ns/inspect`, `kill_feed` | `aiwar`, `slots`, `kill_feed`: yes |
| `features/nodegraph` | `nodegraph` (the feature is OFF) | yes |

Two placements differ from the scholar's:

- `ns/inspect` and `ns/overlay` are *presentation* of NS state (print lines and
  overlay labels), so they go with the features that show them.
- `projectile/orb` is spells-only.

### 3.3 Moves next to the `ws/` module it serves (10 modules)

| Module | Serves | Client needs it? |
|---|---|---|
| `sound_paths` | `ws/sv_world.lua` | no |
| `settings` | `ws/sh_settings.lua`, `ws/sh_nodegraph.lua` | yes |
| `replicated` | `ws/sh_core.lua` | yes |
| `factions` | `ws/sh_factions.lua` (and aiwar) | yes |
| `scoreboard` | `ws/cl_scoreboard.lua` | yes |
| `nav_progress` | `ws/cl_nav_progress.lua`, `ws/sv_nav.lua` | yes |
| `admin_notices` | `ws/sv_world.lua`, `features/editors`, `features/aiwar`, an entity | yes |
| `npc/ragdoll` | `ws/sh_drg_soldier.lua`, `ws/sv_npc_ragdolls.lua` | yes |
| `npc/voices` | `ws/sh_drg_soldier.lua` | yes |
| `localization` | `ws/cl_localization.lua`; the KeyValues reader stays as a structure | yes |

**Home (judgment call):** `ws/<name>.lua` with no realm prefix, loaded as
`WS.require("ws.<name>")`.

- `GM:WSModules` matches only `sh_`, `cl_` or `sv_` prefixes
  (`shared.lua:15-19`), so an unprefixed file is never auto-included.
- `ws/` holds only prefixed files today, so this is a new kind of file there.
  The alternative was a new directory, and the layout rule forbids a
  near-duplicate.
- Client shipping needs one line in `init.lua` (§9.3), and `init.lua` has
  uncommitted changes. So only the server-only `sound_paths` moves before that
  line lands.

---

## 4. The tension with the standing conventions, stated plainly

The operator asked to "refactor foundation logic into controllers". The `lua`
skill (`~/.claude/skills/lua/SKILL.md:110-112`) says: "Controllers coordinate
only… a rule written in a controller belongs in the model."
`rules/code-style.md` says the same and shows it as an ❌ ("the rule written in
the controller (an anemic model)").

**Where the line moves.** It moves between *foundation* and *feature*, not
between model and controller. A mode's rules leave foundation but stay a
model: a pure file in the feature's folder, tested headless.

- Nothing in this plan pastes a rule into `sv.lua`. Doing so would lose LuaJIT
  coverage (feature `sv.lua` files are only read as text by tests, e.g.
  `tests/koth_test.lua:612`).
- The survey found no foundation module that is glue with no test-worthy rule.
  The smallest candidate, `sound_paths` (18 lines), has 3 test cases.

So the "anemic model" rule survives intact. What changes is *which* model
owns a rule.

**Amendments for the operator to approve (not edited here):**

1. `lua` SKILL.md, the layer table (lines 90-95): replace the Model row with
   two rows.
   - `Foundation | foundation/ | Structures, formalisms, gameplay types, NS types: pure, mode-neutral, shared (see the admission rule)`
   - `Feature model | features/<name>/<part>.lua (not sv/cl/sh) | A feature's own rules as pure module(...) files, tested headless`
2. Lines 97-101, "Models are systems, not helpers. A foundation system (rounds,
   capture, payload, npc, spells)…": replace with "A model is pure (ports, time
   and randomness passed in) and tested by scenario. A mode's system (payload,
   spells, bosses) is its feature's model. foundation/ admits only what passes
   the three-part rule, and requires nothing from features/ or ws/."
3. Lines 102-104, "A system is `foundation/<system>.lua`": replace with
   "foundation/ is organised by the four categories. A feature model is
   `features/<name>/<part>.lua`, `model.lua` when the feature has one."
4. Lines 105-109, Strategy (`foundation.rounds.tf2`): replace with "The
   formalism declares the interface in foundation. Each variant lives in the
   feature that chooses it."
5. Lines 110-112: keep, and end with "…belongs in a model: the feature's own
   model unless it passes foundation's admission rule. Never in sv.lua."
6. New `lua` skill bullet on hot reload (see §5, P3): "Keep long-lived model
   state as plain tables driven by module-level functions, or by a module-level
   (not `local`) metatable. A rerun module then applies to live state. Compare
   by value (keys, kinds), never by table identity across a reload."
7. `rules/code-style.md`: "models hold the rules as immutable values". Proposed:
   "…as values: immutable when shared, stored across a reload, or compared; a
   container one owner holds may change in place." This matters only for phase
   3's ledger. Everything else in this plan keeps its immutability.

---

## 5. Simplification patterns (before and after)

**P1. A mode model leaves foundation as a pure feature file** (phase 1 and
later).

```lua
-- before: features/tag/sv.lua:6
local Tag = WS.require("foundation.npc.tag")
-- after: the same file, unchanged, now at features/tag/model.lua
local Tag = WS.require("features.tag.model")
-- tests/tag_test.lua: only the require path changes; every assertion stays
local Tag = T.require("features.tag.model")
```

**P2. One shared structure instead of copies** (phase 1).

```lua
-- before: aiwar/lanes.lua:49 (and seven more)
local function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return sqrt(dx * dx + dy * dy + dz * dz)
end
-- after: above module(...), bound once at load, so the hot path costs the same
local Distance = require("foundation.geometry").Distance
```

**P3. Plain functions over plain data, where state outlives a reload** (phase
3, economy and loadout).

`ws_hotswap_module` reruns a module inside its existing table
(`.devtools/bin/server_root/hotswap.lua:35-41`, `tests/server_hotswap_test.lua:35`).
A rerun replaces module-level functions, so every holder sees them. But
`local Bank = {}; Bank.__index = Bank` (`economy.lua:20-21`) builds a *new*
metatable, and live objects keep the old one.

```lua
-- before
local bank = Economy.New(); bank:Spend(ent, 300)
-- after
local ledger = Economy.New()            -- { balances = {} }, no metatable
Economy.Spend(ledger, ent, 300)         -- a reload changes behaviour for the live ledger
```

**P4. One refusal shape with string kinds** (phase 3). `events.lua:68-81`
already does this.

```lua
-- before: loadout.lua:65-94: six metatables; Refused() looks up getmetatable(err)
-- after: foundation/refusal.lua (Structures)
function Raise(kind, detail) error({ refusal = kind, detail = detail }, 0) end
function Is(err, kinds) return type(err) == "table" and kinds[err.refusal] == true end
function Message(err) return err.refusal .. ": " .. err.detail end
-- loadout: PLAYER = { unknown_weapon = true, ... }; sv_loadout uses Refusal.Message, not tostring
```

String kinds survive a reload. Metatable identity does not (§9.2).

**P5. Key by value, not identity** (phase 3). `loadout.lua:209,222` compares
catalog entries with `==`. Store the class string in `equipped[slot]` and look
the entry up when needed.

**P6. Break a wrong-way edge by moving the vocabulary down** (phase 3).

- Squad: `LEADER` and `MEMBER` become `squad`'s own constants. `slots`
  requires `squad`, the reverse of today.
- Orders: the job constants and `DefenseShare` become an NS module
  (`aiwar/jobs.lua`, NS). `aiwar.lua` re-exports them
  (`PUSH = Jobs.PUSH`) so its callers don't change.
- `EnemyOf` is a war rule. It reaches orders through the soldier port or as a
  plain value. The programmer chooses after reading its body, and it is
  flagged.

---

## 6. What must stay in models, and the main thread

- **Every rule keeps its scenario tests.** AI war tactics (13 test files and
  314 cases load `aiwar`), rounds (16 / 322), capture (6 / 184) and npc
  (13 / 413) all stay pure models, in foundation or in their feature. No rule
  moves into an engine-facing file.
- **No new tick work.**
  - The moves change file paths, not call paths.
  - `geometry.Distance` is bound to a local at load. That is the same upvalue
    access as today's `local function`, with no table lookup per call.
  - P3/P4 change only player-action paths (buy, equip, spend), never per-think
    code.
  - The plan adds no copies to per-tick code. Loadout's copy-on-change can stay.
- **Lazy loading improves.** A moved model loads only on maps whose feature
  asks for it. Server-only models stop being shipped to every client, because
  `init.lua:8-14` ships all of foundation today.

---

## 7. Phase 1: executable now

**Gate: none.** It touches no file in the uncommitted set:

- `addons/sandcastle/cfg/sandcastle_defaults.cfg`
- `foundation/aiwar.lua`, `foundation/aiwar/orders.lua`
- `init.lua`, `ws/cl_ui.lua`
- `tests/aiwar_koth_test.lua`, `tests/aiwar_orders_test.lua`
- all untracked loadout and menu files, and `docs/spawn-menu-design.md`

Stage files by explicit path only. Commit with
`git -c gpg.program=gpg-loopback commit`.

Paths below are relative to `addons/sandcastle/gamemodes/sandcastle/gamemode/` unless they
start with `tests/` or `.devtools/`.

### 7.1 Guard test, written first: `tests/foundation_layers_test.lua`

Data, in the test file:

```lua
local RANK = { structures = 1, formalisms = 2, gameplay = 3, ns = 4 }
local CATEGORY = { ["npc/route"] = "structures", ... }  -- exactly §3.1, plus geometry
local PENDING = { ["aiwar"] = "features/aiwar", ... }   -- §3.2 and §3.3, minus phase-1 moves
local KNOWN_INVERSIONS = {                              -- removed in phase 3
	["aiwar/orders"] = { ["aiwar"] = true },
	["aiwar/squad"] = { ["aiwar/slots"] = true },
}
```

Cases:

1. **"every foundation file is categorised or pending a move, and every entry
   exists"**
   - List the files with `io.popen("find " .. T.ROOT .. "foundation -name '*.lua'")`,
     as `tests/feature_parts_test.lua:17` does.
   - Each file is in exactly one of `CATEGORY` and `PENDING`.
   - Each entry in either table is a file that exists.
   - Each `CATEGORY` value is a key of `RANK`.
2. **"foundation requires nothing from features or ws"**
   - Scan each file for `require%(%s*["']([%w_.]+)["']`.
   - Fail on any name starting `features.` or `ws.`.
3. **"a categorised module requires only categorised modules at its rank or
   below"**
   - For each `foundation.X` that a `CATEGORY` module requires, `X` must be in
     `CATEGORY` with `RANK` ≤ its own.
   - The only exceptions are the edges listed in `KNOWN_INVERSIONS`.

**Proving the guard bites:**

1. Before committing, add `local X = require("features.tag.model")` above
   `module(...)` in `foundation/teams.lua`.
2. Run `luajit tests/foundation_layers_test.lua` and see case 2 fail.
3. Revert the line.

### 7.2 Structure: `foundation/geometry.lua` (test first: `tests/geometry_test.lua`)

- **Interface:** `Distance(a, b) -> number`. Points are `{ x, y, z }`; a
  missing `z` counts as 0. `module(...)`, with `sqrt` captured above it.
- **Test cases:**
  - `{0,0,0}` to `{2,3,6}` is 7.
  - `{x=0,y=0}` to `{x=3,y=4}` is 5, and so is the mixed pair `{0,0,0}` /
    `{x=3,y=4}`.
  - Swapping the points gives the same answer.
  - A point to itself is 0.
- **Replace the local copy** with
  `local Distance = require("foundation.geometry").Distance`, placed above
  `module(...)`, at:
  - `foundation/aiwar/lanes.lua:49`
  - `foundation/aiwar/tactics.lua:33`
  - `foundation/aiwar/hunt.lua:29`
  - `foundation/aiwar/explore.lua:33`
  - `foundation/aiwar/scenario/freeform.lua:29`
  - `foundation/aiwar/scenario/control_points.lua:74`
  - `foundation/ns/inspect.lua:23`

  In each file, drop `sqrt` from the captured locals only if no other use
  remains (tactics, lanes and inspect still use it).
- **`foundation/aiwar/track.lua:7-10`:** replace the body with
  `Distance = Geometry.Distance`. `Track.Distance` stays exported for
  `features/aiwar/sv.lua`, `aiwar/orders.lua` and `tests/aiwar_test.lua`.
- **Leave `nodegraph.lua:42` alone.** Its feature is OFF and it moves later.

### 7.3 Four server-only feature models leave foundation (`git mv`)

| From | To (module name) | Edit consumers | Edit tests (require path only) | Comments to update |
|---|---|---|---|---|
| `foundation/gameplay.lua` | `features/gamemode/gameplay.lua` (`features.gamemode.gameplay`) | `features/gamemode/sv.lua:18` | `tests/gameplay_test.lua:3` (4 cases) | header of the test |
| `foundation/holiday/on_holiday.lua` | `features/holiday/on_holiday.lua` (`features.holiday.on_holiday`) | `features/holiday/sv.lua:92` | `tests/holiday_on_holiday_test.lua:6` (5 cases) | test line 1 |
| `foundation/npc/boss_timer.lua` | `features/boss_timer/model.lua` (`features.boss_timer.model`) | `features/boss_timer/sv.lua:12`, `features/holiday/sv.lua:69` | `tests/boss_timer_test.lua` (20 cases) | `foundation/npc/merasmus.lua:35,58,347` |
| `foundation/npc/tag.lua` | `features/tag/model.lua` (`features.tag.model`) | `features/tag/sv.lua:6` | `tests/tag_test.lua` (8), `tests/headless_hatman_test.lua` (25) | `foundation/npc/headless_hatman.lua:4` |

- The moved files' own `require("foundation.…")` calls stay as they are. A
  feature model may depend on foundation.
- `features/feature_parts_test` checks only `sv.lua` and `cl.lua`, and the
  loader ships only `sh` and `cl`. An extra pure file in a feature folder is
  therefore inert until something requires it. Verified at
  `tests/feature_parts_test.lua:17` and `init.lua:19-30`.
- Leave historical `docs/pass3-halloween.md` and uncommitted
  `docs/spawn-menu-design.md` untouched.

### 7.4 Acceptance criteria (run them)

1. `.devtools/bin/check_lua.sh | tail -2` prints `compiled 458 files`: 455,
   plus `geometry.lua`, `geometry_test.lua` and `foundation_layers_test.lua`.
   It also prints `TOTAL <1805 + cases in the two new test files> passed, 0 failed`.
2. These test files report exactly the same counts as before:
   - `luajit tests/gameplay_test.lua` → `4 passed`
   - `holiday_on_holiday_test.lua` → `5`
   - `boss_timer_test.lua` → `20`
   - `tag_test.lua` → `8`
   - `headless_hatman_test.lua` → `25`
   - `aiwar_lanes_test.lua`, `aiwar_tactics_test.lua` and `aiwar_test.lua`:
     unchanged from the baseline run.
3. `grep -rnE "foundation[./](gameplay|holiday[./]on_holiday|npc[./]tag|npc[./]boss_timer)\b" addon tests`
   prints nothing.
4. `grep -rn "^local function Distance(a, b)" addons/sandcastle/gamemodes/sandcastle/gamemode/foundation`
   prints only `nodegraph.lua`.
5. The four old paths are gone and the four new paths exist (`test -e`).
6. The guard-bites check in §7.1 was seen failing, then reverted.
7. `git diff --stat` on the uncommitted set is byte-identical to before the
   phase. `git show --stat HEAD` lists only phase-1 files.
8. **Live check, no restart:**
   - `ws_hotswap_module` each of the 8 edited foundation modules.
   - `ws_hotswap_feature gamemode OpenTransition`
   - `ws_hotswap_feature holiday OnHolidayOutputs StartBossScenarios`
   - `ws_hotswap_feature boss_timer Run`
   - Then `dt lua` prints non-nil for
     `WS.require("features.tag.model").New` and
     `WS.require("features.holiday.on_holiday").Outputs`.
   - The live `Tag` instance (`features/tag/sv.lua:35`) keeps its old code
     until the next map change. That is expected.

**Deleted:** 4 foundation modules (399 lines) and 8 `Distance` copies (about
32 lines).

---

## 8. Later phases, in order

Each phase keeps the totals. Test files change only their `require` paths
(plus new tests). After a phase that moves modules, the corresponding
`PENDING` rows leave the guard test.

| Phase | Gate | Work | Acceptance (beyond the totals and the guard test) | Deletes from foundation |
|---|---|---|---|---|
| **2** | none | Server-only moves into features whose `sv.lua` doesn't grow: `npc/{profile,spawner}` → `features/npc/`; `rounds/spawn_doors` → `features/rounds/`; `rounds/koth` → `features/koth/model.lua`; `sound_paths` → `ws/sound_paths.lua`. | The same grep for old names prints nothing. `tests/rounds_limits_test.lua:68` (a computed `"foundation.rounds." .. name`) gets a name → path table, so `koth` resolves to `features.koth.model`; all its assertions are unchanged. | 5 modules, 472 lines |
| **3** | The squad fix (`aiwar.lua`, `aiwar/orders.lua` and its tests) and the spawn-menu loadout work are committed | 3a: P6 inversions. Guard test: `KNOWN_INVERSIONS` becomes `{}`. 3b: P3/P4/P5 on `economy` and `loadout`: `foundation/refusal.lua` (Structures), a plain ledger, and classes as keys. | 3a: `luajit tests/foundation_layers_test.lua` passes with an empty `KNOWN_INVERSIONS`. 3b: `tests/economy_test.lua:34` and `tests/loadout_test.lua:60,224` assert the refusal *kind*, not the metatable (the type disappears; the behaviour asserted is the same). A new test proves that a loadout made before a rerun of `foundation.loadout` still has its refusals recognised (§9.2). | 7 refusal metatables, `Bank` and both loadout classes |
| **3c** | none | Done in its own commit: `aiwar/{orders,soldier}` leave the `ns` category for PENDING → `features/aiwar` (Amendment 4), so `KNOWN_INVERSIONS` is `{}`. A mode-neutral NextSoldier tree is architect design, gated on a second NS host. | The guard passes with `KNOWN_INVERSIONS = {}` and fails when an NS module is made to require `foundation.aiwar`. | — |
| — | **The multi-file controllers task** (separate) | It must (1) ship non-`sh`/`cl` feature files that clients need (`init.lua:19-30` ships only `CLIENT_PARTS`), (2) settle the part-file naming (phase 1 uses `model.lua` or the old basename), and (3) ship unprefixed `ws/*.lua` files. | n/a | n/a |
| **4** | Multi-file shipping exists | Client-needed models, smallest dependency first: `capture/hud`; `rounds/{control_points,destruction,text}`; `rounds/arena`; the `payload` system; `hazards`; `haunting` bosses (before spells: `spells/spawn_boss` and `spells/skeleton_horde` require them); `spells` with `projectile/orb`; `holiday`, then `wheel`; `npc/boss_events`; `nbdebug` (`npc/debug`, both overlays); `nodegraph`; §3.3 plumbing into `ws/`. | A client joins a map using each moved feature and `dt lua` on the client loads each moved model. `.devtools/bin/ingame/checks/load.lua:40` lists only `foundation*` names, so extend it to report `features.*` models too. | 57 modules |
| **5** | Phase 3a done, and multi-file has split `features/aiwar/sv.lua` | `aiwar`, `aiwar/{slots,spawns,scenario,scenario/*,soldier,orders}`, `ns/inspect`, `kill_feed` → `features/aiwar/`. | `tests/aiwar_controller_test.lua:535-613`, `aiwar_koth_test.lua:49` and `aiwar_arena_test.lua:125` still pass their `getmetatable(...) == X.Scenario` identity checks, now under the new names. | 11 modules |
| **6** | none | Rename `spectate`'s `train` descriptor field to a generic objective (the scholar's note). Split `localization`'s KeyValues reader into a structure. Remove `PENDING` from the guard. | `PENDING` is empty. `tests/spectate_test.lua` asserts the same behaviour under the new field name. | — |

**Where moved code lands, and which features need splitting.** Every moved
model is its own file, so no `sv.lua` grows. The folders that will grow most:

| Feature | `sv.lua` lines today | Incoming models | Incoming lines | Sequence |
|---|---|---|---|---|
| aiwar | 3423 | 11 | 2.9k | After the split (phase 5) |
| haunting | under 400 | 7 | 4.1k | Phase 4 |
| rounds | 1485 | 4 | 0.2k | Split it with multi-file; the models can come first |
| capture | 1112 (+ cl 401) | 1 | 0.1k | Phase 4 |
| nbdebug | 433 (+ cl 581) | 3 | 0.9k | Phase 4 |
| npc | 855 | 3 | 0.4k | Phase 2 and 4 |
| spells | 483 | 15 | 1.5k | Phase 4 |

---

## 9. Risks

1. **Live reloads (the server never restarts).**
   - A move changes the module's `package.loaded` key. The old copy stays in
     memory until the next map change, and live instances keep its code.
     Example: the `Tag` model at `features/tag/sv.lua:35`.
   - Each phase lists the `ws_hotswap_*` commands for its consumers. They work
     with any dotted name (`hotswap.lua:38`), and a feature hotswap keeps a real
     `WS.require` (`hotswap.lua:54`).
   - A module with *shared state* must not be moved while live code still
     holds the old key. None of the phase 1 or phase 2 modules hold
     module-level state.
2. **Identity-based comparisons.**
   - **Already a live bug:** loadout refusals use per-kind metatables
     (`loadout.lua:65-94`), while loadouts persist across a refresh
     (`ws/sv_loadout.lua:15-17`). A rerun of `foundation.loadout` gives old
     loadouts' methods the old metatables, and `Refused` checks the new ones.
     A player's refusal would then be rethrown as our bug
     (`ws/sv_loadout.lua:40`).
   - Separately, `ws/sh_loadout.lua:12` rebuilds the catalog on refresh while
     `WS.Loadouts` keeps entries from the old one, so `==` at
     `loadout.lua:209,222` misses.
   - Phase 3b (P4, P5) fixes both.
   - Scenario identity tests (phase 5) hold as long as one name loads one copy.
     Acceptance check 3 guards against stale names.
3. **Networked state and client shipping.**
   - The moves change no net message, NW2 variable or event definition. Event
     IDs hash the *event* names, not the module paths.
   - A model a client needs fails to load on the client if it is moved before
     it is shipped. That is why phases 1 and 2 move only models with
     server-only consumers. Verified by a require-closure script over every
     `cl_`/`sh_`/`cl.lua`/`sh.lua`/entity file.
   - Dynamically loaded variants (spells, hazards, projectiles) are not seen by
     a static scan, so phase 4's in-game client check is required.
4. **Tests that could lose coverage.**
   - A move must change only `require` paths. If an assertion has to change,
     the move changed behaviour: stop and report.
   - Two tests change shape and keep their meaning:
     - phase 2, `rounds_limits_test.lua:68` (a computed path);
     - phase 3b, the economy and loadout tests that assert on metatables.
   - Never paste a model into `sv.lua`. Doing so loses headless coverage.
5. **Promoting on a guess** (the scholar's pitfall 4). Nothing moves *into*
   foundation in this plan, except `geometry`, which already has eight users.

## 10. Judgment calls the operator may want to revisit

1. `teams` is placed in Formalisms (with rounds), not Gameplay types. This
   breaks the rounds↔teams cycle without code (§2).
2. `capture`, `combat`, base `projectile`, `loadout`, `players/attributes` and
   `npc/targeting` stay as gameplay types. `npc/brushes` and `npc/clip` join
   NS navigation.
3. `ns/inspect` and `ns/overlay` (presentation) leave with their features,
   unlike the scholar's `ns/*`.
4. `ws/` plumbing lives in unprefixed `ws/<name>.lua` files (§3.3).
5. File naming: `features/<name>/model.lua` for a feature's single model;
   otherwise the old basename. Multi-file controllers may rename.
6. Phase 1 includes `geometry`, which is a structure that stays, alongside the
   moves. It is small, has no gate, and gives the Structures category real
   content.
7. In phase 3, `EnemyOf` reaches NS through the soldier port or as a value.
   Decide after reading it.
8. Folders are not regrouped into `foundation/<category>/`. That would rename
   54 module keys for no behavioural gain. The guard test enforces the
   categories instead.
