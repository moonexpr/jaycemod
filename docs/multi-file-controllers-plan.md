# Multi-file controllers: plan

Status: approved with the operator's decisions of 2026-10-11 (§6). Written
2026-10-11 by the architect.

The operator's goal: "Give features the ability to express multiple files of
controllers to help reduce file length and improve dev navigation."

Foundation phases 4 and 5 (`docs/foundation-simplification-plan.md` §8) are
waiting on this task. §3 below states the exact condition that unblocks each
of them.

Baseline, measured 2026-10-11: `.devtools/bin/check_lua.sh` prints
`compiled 460 files` and `TOTAL 1831 passed, 0 failed`.

---

## 1. The current loader, measured

### 1.1 How a feature loads

All paths below are under `addon/gamemodes/sandcastle/gamemode/` unless they
start with `tests/` or `.devtools/`.

- **A feature is a folder with up to three fixed files.** `foundation/features.lua:17`
  sets `ROOT = "features/"`. `:22` defines the parts `"sh"`, `"sv"` and `"cl"`.
  `:27-29` builds the path as `PartPath(name, part) = ROOT .. name .. "/" .. part .. ".lua"`.
  The loader looks at no other file name.
- **The load order.** `Load` (`features.lua:78-97`) runs `sh.lua` first and
  ignores its return value (`:86`). It then runs the realm's own part,
  `sv.lua` or `cl.lua`, which must return a table (`RunTable`, `:69-75`).
  - The server requires `sv.lua` (`:37-39`).
  - The client requires `sh.lua` or `cl.lua` (`:44-47`).
  - A feature that is still loading and is asked for again raises a cycle
    error (`:104-106`).
- **The loading is lazy.** `WS.Feature(name)` (`ws/sh_core.lua:131-133`)
  calls `Loader:Feature` (`features.lua:101-108`), which loads the feature
  the first time it is asked for. Entities call it on first use, never at
  file top level (`sh_core.lua:95-99`).
- **The file I/O port.** `FeatureFiles` (`sh_core.lua:107-124`) does the I/O.
  - `Exists` calls `file.Exists`.
  - `Run` calls `CompileFile(path)` and then `chunk()` (`:115-119`), so a
    feature file runs in the global environment.
  - `TellClients` fires the `feature_load` event.
- **The loader survives a Lua refresh.** It is kept with
  `WS.FeatureLoader = WS.FeatureLoader or ...` (`sh_core.lua:127-128`),
  because entities hold the controllers it returned.

### 1.2 How a feature reaches clients

- **The source files.** `init.lua:8-14` sends every file under `foundation/`
  recursively (`SendFoundation`). `init.lua:19-30` sends only the files named
  in `CLIENT_PARTS = { "sh", "cl" }` (`features.lua:25`) for each feature
  folder. `init.lua:32-33` sends `ws/sh_*` and `ws/cl_*`, and `:34`
  includes `ws/sv_*` on the server.
- **What is never sent.** Two kinds of file never reach a client today:
  - pure feature models: `features/tag/model.lua`, `features/koth/model.lua`,
    `features/holiday/on_holiday.lua`, `features/boss_timer/model.lua`,
    `features/gamemode/gameplay.lua`, `features/npc/{profile,spawner}.lua`
    and `features/rounds/spawn_doors.lua`;
  - unprefixed `ws/` modules (today only `ws/sound_paths.lua`).

  A client that calls `WS.require` on one of them fails, because
  `CompileFile` (`sh_core.lua:16`) finds no file. The foundation plan
  (`§3.2`, `§3.3`) moved only server-only models for this reason.
- **When the client loads a feature.** The server fires `feature_load` when a
  feature with a client part loads (`features.lua:90,95`). A client that
  joins later gets every loaded feature in load order once it is ready
  (`sh_core.lua:149-151`). The client then calls `WS.Feature` for each name
  (`sh_core.lua:161-163`).
- **`ws/` modules load by name prefix only.** `GM:WSModules(prefix)`
  (`shared.lua:15-19`) globs `ws/<prefix>*.lua`.

### 1.3 How `sv.lua` shares state with its `cl`/`sh` parts

No Lua table is shared between the realms. The parts share four things:

1. **Event definitions in `sh.lua`.** The controller fires them and the view
   listens:
   - `features/capture/sh.lua:1-5`
   - `features/rounds/sh.lua:1-4`
   - `features/nbdebug/sh.lua:1-5`

   `WS.Events.Define` replaces a definition of the same name
   (`foundation/events.lua:373-385`), so defining again is idempotent.
   `Listen` with the same id replaces the old listener (`events.lua:478`).
2. **NW2 and Global2 variables.** For example `ws_round_state`, read through
   `WS.State` (`sh_core.lua:214-216`).
3. **Pure models both realms require.** For example `features/holiday/sh.lua:4`
   requires `foundation.holiday.gift`.
4. **Other features' views, through `WS.Feature`.** For example
   `features/capture/cl.lua:15` calls `WS.Feature("rounds")`.

Inside a realm, a controller keeps its state in two places:

- **Fields of its returned table.** For example the `aiwar` `Controller`
  table at `features/aiwar/sv.lua:654-667`.
- **File-level `local`s:**
  - helpers (`Point`, `ToVector`, `Masks`: `aiwar/sv.lua:57-62`);
  - caches (`hidingSpots` at `:77`, `medicLines` at `:1023`);
  - the soldier port's metatable (`Soldier` at `:142`).

### 1.4 How a feature is hot-swapped

The hot-swap commands live in `.devtools/bin/server_root/hotswap.lua`.

- **`ws_hotswap_module`** (`:35-41`) runs a `WS.require` module's file again
  under `CHUNK_ENV`. `module(...)` keeps the module's table, so every holder
  sees the new functions.
- **`ws_hotswap_feature <name> <Method>...`** (`:51-65`) works in three steps.
  - It compiles **only** `features/<name>/sv.lua` (`:61`).
  - It runs the file in an environment that stubs `hook`, `timer`,
    `concommand`, `cvars`, `net`, `util.AddNetworkString` and
    `WS.Feature` (`:49`, `:55-60`).
  - It copies the named methods from the fresh table onto the live
    controller (`:63`), so the live state stays.
- **What a hot swap cannot do today:**
  - **A new file, or a changed `local` that live code holds, needs a map
    change** (`hotswap.lua:12-13`). The `Soldier` port's methods are one
    case: live soldiers hold the old local metatable.
  - **A name the fresh table lacks deletes the live method** (`:63`). A typo,
    or a method that was renamed, sets `live[name] = nil`. The command
    refuses nothing.
- **Autorefresh does not reach these files.** GMod's autorefresh does not
  rerun `CompileFile`'d files: feature parts and `WS.require` modules
  (`docs/game-events-v2-research.md:312`). Hot swap is the only live path.
- **The tests.** `tests/server_hotswap_test.lua:35-67` covers a module rerun
  and a method copy with zero hooks added.

### 1.5 How tests drive controllers today

- **Loaded and run in a fake GMod:**
  - `tests/aiwar_controller_test.lua:307,559`:
    `setfenv(loadfile(SOURCE), Env(w))()`. Its `Env` (`:193-263`) fakes `WS`,
    `hook.Add` (keyed by event only, `:263`), `concommand`, `cvars`, and so on.
  - `tests/gameplay_settings_test.lua:100` does the same for `editors/sv.lua`.
- **Read as text**, to check contracts and assert what a file does not do:
  - `tests/aiwar_controller_test.lua:1130`
  - `tests/aiwar_soldier_contract_test.lua:17`
  - `tests/nbdebug_contract_test.lua:8-9,28`
  - `tests/capture_master_test.lua:425,441`
  - `tests/capture_point_timer_test.lua:131,145`
  - `tests/koth_test.lua:612,617`
  - `tests/payload_mode_test.lua:379,395`
  - `tests/rounds_modes_test.lua:163`
  - `tests/wheel_test.lua:555`
- **`tests/feature_parts_test.lua:16-25`** asserts that every `sv.lua` and
  `cl.lua` ends with `return <table>`.

### 1.6 Sizes (lines, `wc -l`)

| File | Lines | | File | Lines |
|---|---|---|---|---|
| aiwar/sv.lua | 3424 | | spells/sv.lua | 483 |
| rounds/sv.lua | 1485 | | nbdebug/sv.lua | 433 |
| capture/sv.lua | 1112 | | nodegraph/sv.lua (OFF) | 430 |
| npc/sv.lua | 855 | | capture/cl.lua | 401 |
| nbdebug/cl.lua | 581 | | hazards/sv.lua | 241 |
| rounds/cl.lua | 544 | | wheel/sv.lua | 238 |

Every other feature file is 230 lines or fewer. The tree holds 13,680
feature lines in total.

### 1.7 A defect found while measuring

`Soldier:RouteStale` is defined twice: at `aiwar/sv.lua:301-303` and again at
`:356` (`return false`). The later definition wins, so the first one and the
shut-door replanning it serves (`:1530`, `shutDoorGeneration` at `:1546`)
have no effect. The split keeps the live behaviour (§6, decision 5).

---

## 2. Design

### 2.1 Options

| | Option | Load order and dependencies | Hot swap | Client shipping and naming | Verdict |
|---|---|---|---|---|---|
| A | **Folder per realm**: `features/<name>/sv/*.lua`, `cl/*.lua` | Glob order, so dependencies are implicit. | `hotswap.lua:61` must glob as well. | A part named `cl/hud.lua` has the basename `hud.lua`, so `foundation/replicated.lua:19-22` (`ClientOnly`) would treat a client part's convars as **replicated**: a silent bug. Folders also collide with phase 5's model folder `features/aiwar/scenario/`. | Rejected |
| B | **A manifest file per feature** (`parts.lua` listing files and realms) | Explicit. | Explicit. | It adds a second place to edit for every new file, and a manifest can drift from the files. | Rejected |
| C | **Loader auto-discovers `sv_*.lua`** and runs them after `sv.lua` | Name order, with dependencies implicit. Parts reach each other only through globals or the controller table. | It works, but the loader owns wiring the feature should state. | It ships correctly. | Rejected |
| **D** | **The realm root is the composition root.** `sv.lua` (or `cl.lua`/`sh.lua`) declares the state and runs its parts by name through one helper, `WS.FeatureParts`. Parts are flat files with a realm prefix: `sv_<part>.lua`, `cl_<part>.lua`, `sh_<part>.lua`. | Explicit: the root lists the parts in order. The values one part needs from another are passed as arguments. | Rerunning the root reruns every part in the stubbed environment (§2.4), so it works unchanged. | The prefix matches the `ws/` convention and `replicated.ClientOnly`. The rule is "ship everything except `sv`". | **Recommended** |

**Why D.** The feature loader (`features.lua`) keeps its single entry point
per realm. Lazy loading is unchanged: parts run only when their root runs,
and their root runs only on `WS.Feature`. Hot swap needs no change to find
parts. The root is the one place that shows the feature's shape: its state
and its parts in dependency order. That is the composition root
`rules/code-style.md` asks for. Engine wiring (hooks, console commands,
convar callbacks) may sit in any part, beside the behaviour it triggers
(operator decision 3, §2.4 rule 4).

### 2.2 Naming (settles requirement 2)

One rule for every file in `features/<name>/` and `ws/`, decided by the file
name's prefix. It is the same rule `replicated.ClientOnly` already uses.

| File name | Realm | Role | Loaded by | Sent to clients |
|---|---|---|---|---|
| `sv.lua` | server | Controller root: state and part order (wiring allowed) | `WS.Feature` | no |
| `sv_<part>.lua` | server | Controller part, with its own wiring | its root, through `WS.FeatureParts` | no |
| `cl.lua` / `cl_<part>.lua` | client | View root / view part | `WS.Feature` / its root | yes |
| `sh.lua` / `sh_<part>.lua` | both | Shared root / shared part | the loader, before the realm root / its root | yes |
| anything else (`model.lua`, `<noun>.lua`, `<dir>/<noun>.lua`) | none | A pure `module(...)` model | `WS.require("features.<name>.<noun>")` | **yes** |
| `ws/sv_*`, `ws/sh_*`, `ws/cl_*` | as today | Always-loaded realm modules | `shared.lua`, `init.lua`, `cl_init.lua` | as today |
| `ws/<noun>.lua` (unprefixed) | none | A pure `module(...)` that serves a `ws/` module | `WS.require("ws.<noun>")` | **yes** |

- **The prefix test.** A name is in a realm when it is exactly `sv.lua`,
  `cl.lua` or `sh.lua`, or when it starts with `sv_`, `cl_` or `sh_`.
  A prefix match on a malformed name such as `sv_.lua` still counts as
  server, so it is never sent.
- **Part names.** A part name must match `^(sv|cl|sh)_[%w_]+$`. Parts sit
  directly in `features/<name>/`, never in a subfolder.
- **Model names.** Use `model.lua` when a feature has one model. Otherwise
  use a noun for the concept; the old foundation basename is fine. Phase 1's
  names (`model`, `on_holiday`, `gameplay`, `profile`, `spawner`,
  `spawn_doors`) all fit, so **nothing is renamed**.
- **Pairing a part with its model.** A part that drives one model takes that
  model's noun: `sv_slots.lua` drives `slots.lua` and `sv_soldier.lua`
  implements `soldier.lua`'s port, both after phase 5. Sorted by name, a
  folder then lists the controller parts together and the models together.
- **Amendment to the `lua` skill** (approved by the operator; made as the
  step after M2's acceptance, §4 "After M2"). Under "Load per map, lazily",
  add: "A feature's realm root (`sv.lua`/`cl.lua`/`sh.lua`) is its
  composition root: it declares the state and runs its parts in order.
  Parts are `<realm>_<part>.lua` beside it, run with `WS.FeatureParts`, and
  may register their own hooks, commands and convar callbacks under ids
  unique across the feature. Every other file in the folder is a pure
  model, and all of them are sent to clients."

### 2.3 Interfaces

**`foundation/features.lua`** (stays pure; already in the guard's
`formalisms` category, `tests/foundation_layers_test.lua:39`):

```
CLIENT_DIRS = { "foundation/", "features/", "ws/" }

Realm(fileName) -> SERVER | CLIENT | SHARED | nil
    -- nil: a module (no realm prefix); fileName is a basename
Ships(fileName) -> boolean
    -- Realm(fileName) ~= SERVER
ClientFiles(port, dirs) -> { path, ... }
    -- sorted; recursive through subfolders; only *.lua that Ships
    -- port:Find(dir) -> fileNames, dirNames   (dir ends in "/", relative to the gamemode folder)
PartFile(name, part) -> "features/<name>/<part>.lua"
    -- raises "not a feature part: <part>" unless part matches ^(sv|cl|sh)_[%w_]+$
Parts(port, env, name) -> function(part, ...) -> the part's return values
    -- port:Compile(path) -> function, or nil when the file is missing or does not compile
    -- nil raises "<path> did not compile"; the chunk runs with setfenv(chunk, env) and gets the varargs
```

**`ws/sh_core.lua`**, beside `WS.Feature`:

```
FeatureFiles:Compile(path) -> function | nil      -- CompileFile(GAMEMODE_ROOT .. path)
WS.FeatureParts(env, name) -> Part                -- Features.Parts(FeatureFiles, env, name)
```

**`init.lua:6-34`** becomes the following. The `AddCSLuaFile("shared.lua")`
and `AddCSLuaFile("cl_init.lua")` lines stay.

- **Send:** one loop that calls `AddCSLuaFile` on every path from
  `Features.ClientFiles(port, Features.CLIENT_DIRS)`. Its port's `Find`
  wraps `file.Find(root .. dir .. "*", "LUA")`.
- **Include:** the unchanged `include` loop over `GM:WSModules("sv_")`.
- **Removed:** `SendFoundation` and `SendFeatureClientParts`, which this
  loop replaces (§6, decision 6).

**The root's shape** (format, not code to paste):

```lua
-- features/aiwar/sv.lua
local Controller = { --[[ every state field, nil fields included as comments ]] }
local Part = WS.FeatureParts(getfenv(1), "aiwar")
local Map = Part("sv_map", Controller)                  -- returns its helper table
local Soldier = Part("sv_soldier", Controller, Map)      -- returns the port's metatable
Controller.Soldier = Soldier                             -- so hot swap can reach it (§2.4)
Part("sv_relations", Controller, Map)
-- ... the other parts, in dependency order; each part registers its own hooks
return Controller
```

A part starts with `local Controller, Map = ...` and either returns nothing
or returns its exports.

**Why `getfenv(1)` is passed explicitly.** The helper could read its caller's
environment itself with `getfenv(2)`, but a tail call such as
`return Part(...)` replaces the caller's frame. `getfenv(2)` would then return
the loader's environment, and under hot swap the stubs would be lost. Passing
the root's own environment avoids that, and it gives the right environment
in all three places a root runs:

- live: the global table;
- in `ws_hotswap_feature`: the stubbed environment;
- in a test: the fake environment.

### 2.4 Rules for a split controller

**1. State lives on the controller table, declared in the root.**

- Parts add only **functions** to `Controller`. The root declares every
  state field, `nil` ones included, as `aiwar/sv.lua:654-667` already does
  for most of them.
- Fields that `aiwar` assigns today outside the literal move into it:
  - `gates`, `zones`, `shutDoors`, `postCache` and `baseCache` (reset at
    `:3362-3373`);
  - `shutDoorGeneration` (`:1546`);
  - `slotStore`, which is wiring (`:2240`).
- Hot swap copies methods and leaves state alone (`hotswap.lua:63`), so
  this rule is what makes a swap safe.

**2. Part-level locals hold only constants, functions, and caches that can be
rebuilt.**

- A hot-swapped method is a fresh closure over the fresh run's locals, so a
  cache it reads starts empty and is rebuilt. That is safe only for caches.
- `aiwar`'s `hidingSpots` (`:77`) and `medicLines` (`:1023`) are caches.
- Anything that is not a cache goes on `Controller`.

**3. Values pass between parts as arguments and return values.**

- One part never reads another's locals, and nothing becomes global.
- A hot-path part rebinds what it uses at its top
  (`local Point, ToVector = Map.Point, Map.ToVector`), so each call
  reads an upvalue, not a table field, and the tick costs nothing extra.

**4. Wiring may live anywhere: in the root or in any part** (operator
decision 3).

- Wiring means `hook.Add`, `concommand.Add`, `cvars.AddChangeCallback`,
  `timer.Create` and `WS.Events.Listen`. Put it in the part whose behaviour
  it triggers (aiwar's `Tick` hook in `sv_enlist`, its commands in
  `sv_commands`). The root keeps only wiring that spans parts, such as
  aiwar's `PostCleanupMap` reset of state from several parts.
- **Every wiring id is a stable literal, unique across the feature's
  files** in that realm: each `(event, id)` pair for hooks, each command
  name, each `(convar, id)` pair for callbacks, each timer name and each
  `(event, id)` pair for `Listen`. GMod *replaces* a registration with the
  same key rather than adding one. So two parts that use the same key do
  not double-register; the later one silently drops the earlier one. Two
  M2 checks catch it: a static scan of literal ids (f) and a run-time
  recorder (f2) that also sees ids built at run time, such as those of
  aiwar's `AdminCommand` wrapper (`aiwar/sv.lua:3051`).
- **A hook body delegates to a `Controller` method** in one line or a few
  (`Controller:Think(CurTime())`). The live closure looks the method up by
  name on every call, so a hot-swapped method takes effect through it.
  Logic written inline in a hook closure cannot be swapped and needs a map
  change, as today.
- **Nothing is registered anonymously at load:** no `timer.Simple` and no
  unnamed timer at a part's top level outside a stubbed library. Such a
  registration has no key that can replace it. `rounds/sv.lua:1450`'s
  `timer.Simple(0, ...)` is a one-shot and is allowed; it stays in the
  root.

**How hot swap stays clean when parts register wiring.**

1. `ws_hotswap_feature` reruns the root in its stubbed environment
   (`hotswap.lua:55-62`). The root passes that environment to every part
   with `getfenv(1)` (§2.3). So the parts' `hook`, `timer`, `concommand`,
   `cvars` and `net` are the inert stubs, and the rerun registers nothing.
2. The live registrations stay. They hold the live `Controller`, and
   because hook bodies call methods by name, the copied methods take effect
   at the next call.
3. `WS.Events.Listen` is not stubbed today (`hotswap.lua:49,55`). A part's
   `Listen` in a rerun would replace the live listener with a closure over
   the fresh, unused `Controller`. M3 adds `Events.Listen` and
   `Events.Ignore` to the stubs. No `sv.lua` calls `Listen` at load today,
   so this closes a gap that wiring-anywhere opens.
4. Outside hot swap (a map change rebuilds the Lua state), a rerun of the
   same parts registers the same keys, which GMod replaces, so a feature's
   wiring can never stack.

**5. Each method name is defined once per feature realm,** across the root and
its parts. A second definition silently overrides the first, as
`RouteStale` does (§1.7). A test enforces this.

**6. Parts do no work when they load beyond definitions** and idempotent
registrations: `CreateConVar`, `WS.Events.Define`, `WS.require`. This is
the same as `sv.lua` today. Parts run once, when the feature loads, so
lazy loading holds.

**7. Nothing `WS.require`s a part.** Parts are not modules, and
`package.loaded` never holds `features.<name>.sv_*`.

**8. Hot swap** (`ws_hotswap_feature`):

- **Parts are reached unchanged.** Rerunning `sv.lua` reruns every part
  with the stubs (rule 4 and §2.3).
- **The command gains three behaviours,** each written test-first in M3:
  - **`WS.Events.Listen`/`Ignore` are stubbed** in the rerun, as rule 4
    explains.
  - **`Table.Method` names.** `ws_hotswap_feature aiwar Soldier.Move` copies
    `fresh.Soldier.Move` onto `live.Soldier`. Live ports use `live.Soldier`
    as their metatable, so they pick it up. Today the soldier port cannot be
    swapped at all.
  - **All-or-nothing refusal.** If any requested name is not a function on
    the fresh side, or if `live.<Table>` is not a table, the command tells
    the caller which names failed and copies **nothing**. That fixes
    §1.4's deletion hazard.
- **A new `sv_` part** is picked up by a hot swap, because the rerun
  compiles from disk. **A new `cl_`/`sh_` part** needs a map change, because
  it is sent at gamemode load.

### 2.5 How tests drive split controllers

- **Harness helpers** in `tests/harness.lua`:
  - **`T.FeatureParts(env, name)`** is `Features.Parts` with a port whose
    `Compile(path)` returns `loadfile(T.ROOT .. path)`, or `nil`. A test's
    fake `WS` adds `FeatureParts = T.FeatureParts`. The aiwar `Env`
    (`tests/aiwar_controller_test.lua:193-263`) gets this in M4.
  - **`T.RealmSource(name, realm)`** returns the text of
    `features/<name>/<realm>.lua` followed by every `<realm>_*.lua` in name
    order. Every text-reading test in §1.5 switches to it in M2, **before
    any split**, so that a split cannot hide a forbidden string in a part.
- **Behaviour tests stay as they are.** They load the root, which loads its
  parts, and their assertions do not change. If an assertion has to change
  during a split, the split changed behaviour: stop and report.

---

## 3. The three requirements, and what unblocks phases 4 and 5

| Requirement (`foundation-simplification-plan.md` §8 row "multi-file controllers") | Met by |
|---|---|
| (1) Send clients the non-`sh`/`cl` feature files they need | `Features.ClientFiles` sends every file under `features/` (any depth) except `sv.lua`/`sv_*`. Phase 4's client models then need no extra wiring. |
| (2) Settle part-file naming | §2.2: realm prefix means part; no prefix means pure model; `model.lua` for a feature's single model. |
| (3) Send unprefixed `ws/*.lua` files | The same `ClientFiles` walk covers `ws/`, sending everything except `ws/sv_*`. |

**Phase 4 is unblocked when M1 is committed** (it does not wait on M2-M4).
That requires all three of the following:

- **Headless tests pass:**
  - `luajit tests/features_test.lua` (the `Realm`/`Ships`/`ClientFiles`
    cases);
  - `luajit tests/client_shipping_test.lua`;
  - `.devtools/bin/check_lua.sh` with `0 failed`.
- **`init.lua` sends through `Features.ClientFiles`:** `git grep -n
  ClientFiles addon/gamemodes/sandcastle/gamemode/init.lua` prints one line,
  and `git grep -n "SendFeatureClientParts\|SendFoundation"` prints nothing.
- **A client check, run with the operator present.** On the running server,
  do a `changelevel`, not a restart. Then, on a client started with
  `.devtools/bin/gmod_client.py start`, run
  `dt lua --realm cl 'print("ship", pcall(WS.require, "features.tag.model"), pcall(WS.require, "ws.sound_paths"))'`.
  The client's con log under `data/ws_tests/client/` must show `ship true
  table true table`. The client launches in the operator's game bottle, so
  the operator must be present for this step.

**Phase 5 is unblocked when M4 is committed** (phase 3a is already done,
`f892e2c`). That requires all of the following:

- **The split is in place:** `features/aiwar/sv.lua` is the root, of at most
  300 lines, and `PENDING_SPLIT` in `tests/feature_parts_test.lua` no longer
  lists `aiwar/sv.lua`.
- **The structural tests pass:** every part is named by its root, no
  method is defined twice, wiring ids are unique, and every state field is
  declared.
- **`.devtools/bin/check_lua.sh` prints `0 failed`,** with the passed count
  no lower than M3's.
- **The live checks pass:** after `changelevel pl_badwater`, the `aiwar` and
  `aiwar_sitting` in-game checks (`.devtools/bin/ingame/checks/aiwar.lua`)
  pass, and both `ws_hotswap_feature aiwar Think` and
  `ws_hotswap_feature aiwar Soldier.Move` print `swapped`.
- **No name collides with phase 5's models.** Phase 5's incoming files are
  unprefixed models (`aiwar.lua`, `slots.lua`, `spawns.lua`, `scenario.lua`,
  `scenario/*.lua`, `soldier.lua`, `orders.lua`, `inspect.lua`,
  `kill_feed.lua`), so none can collide with an `sv_` part.

---

## 4. Phased plan

Each phase is one commit. Write its tests first and watch them fail before
writing the code. After each phase, `.devtools/bin/check_lua.sh` prints
`0 failed`, and the passed count goes up by exactly the number of new
assertions. Commit with `git -c gpg.program=gpg-loopback commit`.

### M1. Sending files to clients (unblocks phase 4)

**Status (2026-10-11): implemented and committed. The server check passed: after
`changelevel pl_badwater` the server log has no Lua error, and server-side
`WS.require("features.tag.model")` and `WS.require("ws.sound_paths")` return
tables. OPEN: the client check (`ship true table true table` on a client after
a changelevel) needs the operator present. Until it passes, foundation phase 4
and any `cl_`/`sh_` part split (M5's `rounds/cl.lua`, `nbdebug/cl.lua`,
`capture/cl.lua`) stay blocked. M2–M4 may proceed (reviewer, M1 gate).**

**Tests first.**

- `tests/features_test.lua`: `Realm` cases.
  - `sv.lua`, `sv_soldier.lua` and `sv_.lua` give `SERVER`.
  - `cl.lua` and `cl_hud.lua` give `CLIENT`.
  - `sh.lua` and `sh_events.lua` give `SHARED`.
  - `model.lua`, `on_holiday.lua`, `sound_paths.lua` and `svc.lua` give `nil`.
- `tests/features_test.lua`: `ClientFiles` over a fake port tree.
  - Excluded: a top-level `sv.lua` and `sv_x.lua`, and `ws/sv_world.lua`.
  - Included: `cl.lua`, `sh.lua`, `cl_x.lua`, `model.lua`, a nested
    `features/a/scenario/koth.lua`, `ws/sound_paths.lua`, `ws/sh_core.lua`
    and `foundation/teams.lua`.
  - The output is sorted.
- **New `tests/client_shipping_test.lua`** runs `ClientFiles` over the real
  tree (a port over `io.popen("find ...")`). It asserts four things.
  - **Required files are present:** the set contains
    `features/tag/model.lua`, `ws/sound_paths.lua`,
    `features/capture/cl.lua` and `foundation/teams.lua`.
  - **No server file is sent:** no `sv.lua` or `sv_*` path appears.
  - **The set grows only by modules.** It equals the old rule's set
    (recomputed in the test from `init.lua`'s old logic: all of
    `foundation/`, each feature's `sh`/`cl`, and `ws/sh_*`/`cl_*`) plus
    exactly the files under `features/` and `ws/` whose `Realm` is `nil`.
  - **Every `WS.require` target reaches the client.** For every literal
    `WS.require("features.…")` or `WS.require("ws.…")` in a client-realm
    file, the target path is in the set. The client-realm files are
    `ws/sh_*`, `ws/cl_*`, the feature files whose `Realm` is `CLIENT` or
    `SHARED`, and every file under `entities/`.

**Code.**

- Add `Realm`, `Ships`, `ClientFiles` and `CLIENT_DIRS` to
  `foundation/features.lua`.
- Replace `init.lua:6-34` as in §2.3.

**Acceptance.** All of the following, plus the phase 4 unblock conditions in
§3:

- **The headless tests pass:** `luajit tests/features_test.lua` and
  `luajit tests/client_shipping_test.lua` both print `0 failed`.
- **`luajit tests/foundation_layers_test.lua` passes,** which shows
  `features.lua` still requires nothing from `features/` or `ws/`.
- **The server loads cleanly:** after a `changelevel` on the running
  server, the server console shows no Lua error from `init.lua`.

### M2. Realm parts and the test tooling

**Tests first.**

- `tests/features_test.lua` gains `PartFile` and `Parts` cases.
  - `PartFile` refuses `soldier`, `../x`, `sv_a.b` and `sv_` with
    `not a feature part`.
  - `Parts` compiles exactly `features/aiwar/sv_map.lua`, runs the chunk
    with the `env` it was given (the chunk reads a marker global from that
    env), passes the varargs, and returns the chunk's values.
  - A port that returns `nil` raises an error naming the path.
- `tests/feature_parts_test.lua` gains these checks:
  - **(a) No orphan or double-loaded parts.** Every `<realm>_*.lua` in a
    feature folder is named by exactly one `Part("<stem>"` in that realm's
    root. A part that no root names fails, and so does one named twice.
  - **(b) Parts sit at the top level.** No realm-prefixed file sits in a
    feature subfolder.
  - **(c) Only roots call `WS.FeatureParts`,** and each passes its own
    folder name.
  - **(d) Nothing requires a part.** No `WS.require("features.%w+.%a%a_`
    appears anywhere in the gamemode.
  - **(e) Each method is defined once** per feature realm, across the root
    and its parts. This covers every `function <T>[:.]<Name>`.
  - **(f) Literal wiring ids are unique** per feature realm, across the
    root and all its parts:
    - hooks: each `hook.Add("<event>", "<id>"` pair;
    - commands: each `concommand.Add("<name>"`;
    - convar callbacks: each `cvars.AddChangeCallback("<cvar>", …, "<id>")`
      pair;
    - timers: each `timer.Create("<name>"` (a name in a file-level
      constant counts: resolve `local NAME = "..."` in the same file);
    - listeners: each `Events.Listen("<event>", "<id>"` pair.

    The test must fail on a fixture feature with two parts that both call
    `hook.Add("Think", "ws_x", …)`, and on one whose root and part both
    call `concommand.Add("ws_x_report", …)`.
  - **(f2) Run-time double-registration recorder.** New harness helper
    `T.Wiring()`. It returns fake `hook`, `concommand`, `cvars`, `timer`
    and `Events` tables that record every registration as
    `kind, key` (for example `hook Think ws_aiwar`) and a
    `:Duplicates()` list of keys registered more than once in one load.
    A feature's loaded-root test (for aiwar, `tests/aiwar_controller_test.lua`'s
    `Env`, which keeps its own `w.hooks[event]` mapping on top) loads the
    root once and asserts `Duplicates()` is empty. This catches ids built
    at run time, which (f) cannot see. The recorder's self-test registers
    the same hook key twice and expects one duplicate.
  - **(g) The size ratchet.** No realm file is over 600 lines, except
    those in `PENDING_SPLIT = { "aiwar/sv.lua", "rounds/sv.lua",
    "capture/sv.lua", "npc/sv.lua" }`. Every `PENDING_SPLIT` entry must
    exist and must still be over 600 lines, so a split that lands must
    remove its entry.

  Check (e) **fails today** on `aiwar`'s `Soldier:RouteStale` (§1.7). M2
  deletes the dead definition at `aiwar/sv.lua:301-303`, which leaves the
  live behaviour as it is (operator decision 5).
- **Harness self-tests** for `T.FeatureParts` and `T.RealmSource`, using a
  temp feature under the scratch root. `T.RealmSource` must work on a
  feature that has no parts.
- **Switch every text-reading test in §1.5 to `T.RealmSource`.** Their
  assertions do not change.

**Code.**

- Add `PartFile` and `Parts` to `features.lua`.
- Add `FeatureFiles:Compile` and `WS.FeatureParts` to `sh_core.lua`.
- Add the harness helpers.
- Delete the dead `RouteStale`.

**Acceptance.**

- **The tests pass:** `luajit tests/feature_parts_test.lua` and
  `luajit tests/features_test.lua` both print `0 failed`.
- **Text-reading tests still read only `sv.lua`:**
  `git grep -n 'features/[a-z_]*/sv.lua' tests/` prints only `features_test`
  path cases, the `replicated_test` source strings and the
  `aiwar_controller_test` `SOURCE`, which loads the root.
- **The recorder runs on aiwar before any split:** `luajit
  tests/aiwar_controller_test.lua` prints `0 failed` with the new
  "registers each wiring key once" test in it.

### After M2: amend the `lua` skill

Once M2's acceptance passes and M2 is committed, make the approved
amendment in §2.2 to `~/.claude/skills/lua/SKILL.md` (edit it in the config
repo and redeploy, as the config's CLAUDE.md says). That is the only file
this step touches. Acceptance: `grep -n "WS.FeatureParts"
~/.claude/skills/lua/SKILL.md` prints the new bullet.

### M3. Hot swap for split features

**Tests first,** in `tests/server_hotswap_test.lua`. The test's fake `WS`
gains a `FeatureParts` built on the fake `CompileFile`.

- **A swap reaches a method defined in a part.** A feature has a root that
  calls `Part("sv_area", Controller)`, and a part that calls `hook.Add`
  and `concommand.Add` and defines `Controller:Old`. Swapping `Old` updates
  the live method, adds no hook and registers no command.
- **A `Table.Method` name reaches instances.** A live instance whose
  metatable is `live.Soldier` sees the new `Soldier.Move`.
- **A name missing from the fresh side is refused.** The live method
  stays, the caller is told the name, and nothing is copied, including the
  valid names in the same call.
- **An unknown table is refused.** `Nope.Move` is refused and nothing is
  copied.
- **A part's listener is not rebound.** A part that calls
  `WS.Events.Listen("x", "ws_x", fn)` at load leaves the live listener in
  place after a swap: the fake `Events` records zero `Listen` calls during
  the rerun.

**Code.** In `.devtools/bin/server_root/hotswap.lua`:

- change `:51-65`;
- update the usage comment at `:8-13`.

**Acceptance.**

- **The tests pass:** `luajit tests/server_hotswap_test.lua` prints
  `0 failed`.
- **The live server swaps safely.** After a map change, on the running
  server:
  - `ws_hotswap_feature capture` with an existing method prints `swapped`;
  - with a misspelled method it prints a refusal, and the feature still
    works.

### M4. Split `features/aiwar/sv.lua` (unblocks phase 5)

**The map of parts, measured from the code.** Section boundaries come from
the file's own `-- Name ---` headers. Cross-part names come from a scan of
every file-level `local` against the sections that use it.

| File | From `aiwar/sv.lua` lines | ≈ lines | Responsibility | Takes | Returns |
|---|---|---|---|---|---|
| `sv.lua` (root) | header, 650-667 (state, plus the fields of §2.4 rule 1), 2229-2240 (`SlotFile`, the I/O port), `PostCleanupMap` 3362-3373 (resets state of several parts) | ~120 | State, parts in order, cross-part reset | — | `Controller` |
| `sv_map.lua` | 57-136; `WorldWalkClear` 321, `OnFloor` 340, `Clear`/`ClearSpotNear` 1116-1137, `GroundBelow` 1225, `CartRadius` 1349, `TeamSize`/`LoadedFeature`/`RoundsModeName`/`StalemateIsRound` 669-698 | ~200 | How the war reads the map: points, masks, spawn spots, hiding spots, doors, ground | Controller | `Map` (helper table) |
| `sv_soldier.lua` | 137-649 | ~510 | The soldier port over a DrGBase soldier, and its gadgets | Controller, Map | `Soldier` (also `ARRIVED`) |
| `sv_relations.lua` | 700-937; hooks `EntityFireBullets`, `WSRoundWin`, `WSMatchWin` | ~255 | Relationships, humiliation, teammates passing through each other | Controller, Map | — |
| `sv_enlist.lua` | 938-1222; `ApplyHeal` 3220-3263, `StandSeated` 3264, `CarrySeated` 3291, `Fallen` 3347; hooks `Tick` (`ws_aiwar_move`), `OnEntityCreated`, `EntityRemoved`, `EntityTakeDamage`, `OnNPCKilled`, `WSRoundActivate`; the `ws_aiwar_sitting_enabled` callback | ~440 | Enlisting, kits, medics, discharge, spawning, waves, seats | Controller, Map, Soldier | — |
| `sv_obstacles.lua` | 1246-1561, 2166-2219 | ~370 | Setup gates, forcefields, carts in the way, setup zone, doors opened and shut, spawn doors | Controller, Map | — |
| `sv_posts.lua` | 1562-1773 | ~210 | The observer and the posts where soldiers hold their line | Controller, Map | `WATCH_INTERVAL` |
| `sv_field.lua` | 1223-1245, 1774-2165; the `Think` hook | ~425 | Tracks, the field snapshot, lanes, `Think`, sight | Controller, Map, Posts exports | — |
| `sv_slots.lua` | 2220-2435 minus `SlotFile` | ~205 | Slot plan, sizes, pins, sync to viewers | Controller | — |
| `sv_war.lua` | 2436-2632; hooks `WSFreeze`, `WSSuddenDeathOver`, `WSTeamCombatants`, `WSHaveCombatants`; the `ns_soldiers_paused` and `ns_squads_*` callbacks | ~260 | `Start`/`End`, pausing, squads and jobs by hand | Controller, Map | — |
| `sv_report.lua` | 2633-3031 | ~400 | `Describe`, the reports, `SendDebug` | Controller, Map, Soldier | — |
| `sv_commands.lua` | 3032-3210 (with the `WSNbDebugNpcs` hook) | ~180 | `ws_aiwar_*` and `ns_*` console commands | Controller | — |

Each file then requires only the `foundation` modules it uses. The scan
shows, for example, `Posts` used only by posts, `Hearing` and `Factions` by
relations, and `Inspect` and `Tuning` by the debug code. The largest part
is `sv_soldier.lua` at about 510 lines.

**Tests first.**

- Add `FeatureParts = T.FeatureParts` to the aiwar test `Env`. Every
  existing aiwar test must still pass against the **unsplit** file first.
- Before moving code, run the (f2) recorder on the unsplit file and save
  its sorted key list to the session scratchpad. After the split, the list
  must be identical: the split moves wiring, it does not add, drop or
  rename any.
- **New check (h) in `tests/feature_parts_test.lua`:** every
  `self.<lower>` assignment inside a `function Controller[:.]` body, in any
  `aiwar` part, names a key that the root's `Controller = {` literal
  declares. A key listed as a `-- name = nil` comment line counts as
  declared. Apply the check to every split feature afterwards.

**Code.**

- Move the code into the parts listed above, verbatim apart from the
  locals each part now takes as arguments. Move no rule and change no
  rule.
- Remove `aiwar/sv.lua` from `PENDING_SPLIT`.

**Acceptance.** These are the phase 5 unblock conditions in §3, plus the
following:

- **The aiwar tests pass unchanged:** `luajit tests/aiwar_controller_test.lua`,
  `luajit tests/aiwar_soldier_contract_test.lua` and
  `luajit tests/nbdebug_contract_test.lua` each print `0 failed`, with the
  same assertion count as before the split.
- **The file sizes hold:** `wc -l addon/gamemodes/sandcastle/gamemode/features/aiwar/sv*.lua`
  shows the root at 300 lines or fewer and every part at 600 or fewer.
- **Lazy loading still holds:** the `load` in-game check on `pl_badwater`
  still reports `aiwar` among `lacks` until `mp_aiwar_start`
  (`.devtools/bin/ingame_tests.py:98-102`).
  - **On the operator's running server,** do a `changelevel` and run
    `dt lua 'return WS.FeatureLoaded("aiwar")'`. It prints `false`.
  - **Use `ingame_tests.py` only with the operator's agreement,** because
    it starts and stops its own server.

### M5 onward. The other long controllers, in priority order

**Priority order.** Each is ranked by length and by the foundation phase
waiting on it. Run the same cross-section scan first, and adjust the
boundaries to what it shows.

**1. `rounds/sv.lua` (1485).** The foundation plan says to split it with
multi-file (§8). Phase 4 brings in 4 models.

| File | Lines today | ≈ lines | Contents |
|---|---|---|---|
| `sv.lua` (root) | 1-190, 678-795, 1252-1305, 1384-1485 | ~460 | State, mode and holds, round state, thinking, map setup, wiring |
| `sv_players.lua` | 191-342 | ~150 | Players, the spawn doors of a stopped game |
| `sv_timers.lua` | 396-677, 1306-1383 | ~360 | Timers, team clocks and round limits |
| `sv_effects.lua` | 796-1011 | ~215 | Sounds, `logic_auto`, effects |
| `sv_gamerules.lua` | 343-395, 1012-1251 | ~295 | The proxy, the gamerules surface, inputs |

**2. `capture/sv.lua` (1112).** It comes before phase 4's `capture/hud`
move, so `sv_hud` pairs with `hud.lua`.

| File | Lines today | ≈ lines | Contents |
|---|---|---|---|
| `sv.lua` (root) | 1-75, 480-513, 1010-1020 | ~120 | Root |
| `sv_points.lua` | 76-479 | ~405 | Point set, queries, changes |
| `sv_master.lua` | 514-618, 1021-1112 | ~200 | Master, `tf_logic_cp_timer` |
| `sv_areas.lua` | 619-867 | ~250 | Capture areas |
| `sv_hud.lua` | 868-1009 | ~140 | HUD |

**3. `npc/sv.lua` (855).**

| File | Lines today | ≈ lines | Contents |
|---|---|---|---|
| `sv.lua` (root) | 1-165, plus hooks | — | Bind, spawn, bosses |
| `sv_blockers.lua` | 166-391 | ~225 | Spawn rooms, brushes, blockers, doors |
| `sv_routes.lua` | 392-612 | ~220 | Path cost, `NavGraph`, route requests, searches, waypoints |
| `sv_profile.lua` | 613-800 | ~190 | Path profiling, observing, the bench and its commands; pairs with `profile.lua` |

**4. Not split.** These are under 600 lines: `nbdebug/cl.lua` (581),
`rounds/cl.lua` (544), `spells/sv.lua` (483) and `nbdebug/sv.lua` (433).
Split one only if phase 4 pushes it over 600, which the ratchet in check
(g) then flags. **Run the first `cl_` part split with the operator
present.** It is the first time a client part loads through
`WS.FeatureParts`, so check it on a connected client after a `changelevel`.

**Acceptance for each of these phases** follows M4's pattern:

- the feature's entry leaves `PENDING_SPLIT`;
- the existing tests for that feature pass unchanged, with the same
  assertion count;
- the feature's in-game check passes after a `changelevel`;
- a hot swap of one method defined in a part prints `swapped`.

The checks per feature:

| Feature | In-game check |
|---|---|
| rounds | `koth`, `cp_capture`, `payload` |
| capture | `cp_capture`, `capture_cleanup`, `sandbox_capture` |
| npc | `bosses`, `skeletons` |

---

## 5. Risks

1. **Hot-swap ordering.**
   - **Values passed between parts.** A rerun builds a fresh root and runs
     every part in its listed order, so the exports one part passes to the
     next (`Map`, `Soldier`) are always complete when they are used.
   - **Fresh closures.** A swapped method is a fresh closure over the fresh
     helpers. Rule 2 (§2.4) keeps that safe: part locals hold only caches,
     never state.
   - **Changes a swap does not reach:**
     - logic inline in a live hook closure, in the root or any part
       (§2.4 rule 4 keeps hook bodies to method calls);
     - a cross-part export captured at load.

     Both still need a map change, as `hotswap.lua:12-13` already says.
2. **Hooks, net messages or events registered twice.**
   - **Within one feature.** Wiring may sit in any file, so this risk grows
     with the decision. Check (f) catches duplicate literal keys across a
     feature's files; the (f2) recorder catches keys built at run time.
     Check (e) catches duplicate method names. Without them, GMod's
     replace-by-key would make one part's hook silently vanish.
   - **On a rerun.** Hot swap stubs `hook`, `timer`, `concommand`, `cvars`
     and `net`, and after M3 `WS.Events.Listen`/`Ignore` as well, so a
     rerun registers nothing and live closures keep the live controller.
     `WS.Events.Define` is idempotent by name (`events.lua:373-385`).
     `CreateConVar` on an existing name returns the existing convar.
   - **Remaining gap: `timer.Create` and `hook.Add` from inside a
     function.** One called at run time, not at load, is not stubbed. That
     is the same as today.
3. **Globals.**
   - **No new globals.** Parts run in the root's environment and take
     their dependencies as arguments, so they define no globals.
   - **A part that forgets `local`** leaks into `_G` exactly as `sv.lua`
     would today. `luajit -bl part.lua | grep GSET` lists such leaks, and
     M2's check (c) keeps the call sites to roots.
   - **No module name changes.** `WS.FeatureParts` adds nothing to
     `package.loaded`.
4. **Clients missing files.**
   - **What the headless check misses.** `client_shipping_test.lua` sees
     only literal `WS.require` strings. Variants loaded dynamically (spells,
     hazards, projectiles, foundation plan §9.3) are not visible to it, so
     phase 4 keeps its in-game client check.
   - **New `cl_`/`sh_` files need a map change.** A client part or model
     added after the server loaded the gamemode is not sent until a map
     change, because `AddCSLuaFile` runs at gamemode load.
   - **Server-only models are now downloadable.** Sending is not running,
     and foundation already sends everything (`init.lua:6-14`), so this is
     consistent (operator decision 1).
5. **Lazy-loading regressions.**
   - **Parts load only with their root,** inside `WS.Feature`, and check (c)
     forbids a call to `WS.FeatureParts` from anywhere else.
   - **The in-game proof** is the `load` check's `lacks` list (`ingame_tests.py:98-102`),
     run once per split.
   - **`AddCSLuaFile` sends but does not run,** so sending more files leaves
     client RAM unchanged until a feature loads.
6. **Replicated convars.** A convar created in a part keeps its flags only
   if `replicated.ClientOnly` classifies the part correctly. Flat prefixed
   names make `cl_<part>.lua` client-only and `sv_<part>.lua` not, with no
   change to `replicated.lua:19-22`. Option A would have broken this.
7. **The main thread.**
   - **Extra cost at load.** Each part adds one `CompileFile` when its
     feature first loads.
   - **No extra cost per tick.** Method dispatch is the same table lookup,
     and hot paths rebind their exports as upvalues (§2.4 rule 3).
   - **A hot swap recompiles every part.** That is about the same work as
     today's full `sv.lua` compile, and it happens only on an admin
     command.
8. **Out of scope, but noted.** `ws/sh_aiwar.lua` and `ws/cl_aiwar_slots.lua`
   are always loaded, although their content belongs to one mode. They
   break the per-map rule, and this plan leaves them as they are.

---

## 6. Decisions

The operator decided items 1-5 on 2026-10-11; items 6-9 are the
architect's calls and stand unless revisited.

1. **Send everything except `sv`** (operator). Every file except `sv.lua`
   and `sv_*` is sent, server-only models included, as `foundation/` is.
2. **Size limits** (operator): 600 lines per realm file (the ratchet in
   check (g)); 300 for the aiwar root. Pure model files have no limit.
3. **Wiring anywhere** (operator). A part may register its own hooks,
   console commands, convar callbacks, timers and listeners; the root
   stays the composition root for state and part order. Ids are stable
   literals unique across the feature, enforced by checks (f) and (f2);
   hot swap stays clean as §2.4 rule 4 explains.
4. **The `lua` skill is amended after M2's acceptance** (operator), with the
   text in §2.2. A separate step; this plan does not edit the skill.
5. **The dead `Soldier:RouteStale` (`aiwar/sv.lua:301-303`) is deleted in
   M2, keeping the live `return false`** (operator). Replanning when a
   door is found shut is a separate NextSoldier change with its own failing
   test first; the shut-door counter (`:1546`) is left until then.
6. **One walk for the three folders.** `init.lua`'s `SendFoundation`
   becomes part of the single `ClientFiles` walk. Foundation has no realm
   prefixes, so the set of files it sends is unchanged.
7. **Parts are listed in the root,** not discovered: the order is explicit,
   at the cost of one line per part.
8. **`Table.Method` hot swap** is added in M3. Without it the soldier port,
   about 510 lines, cannot be swapped at all.
9. **Part names:**
   - `sv_map` for the war's helpers that read the map. `sv_world` would
     collide by name with `ws/sv_world.lua`.
   - `sv_enlist` takes medic healing and seats, and the hooks that drive
     them, because both act on enlisted soldiers' entries every tick.
