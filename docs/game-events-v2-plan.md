# Game events v2: the plan

**Architect, 2026-10-08, main at 38eb752.** This plan turns
`docs/game-events-v2.md` (the spec), `docs/game-events-v2-research.md` (the
research) and the scholar's verdicts at the end of it into five phases, each
with acceptance criteria an agent can check by running something. **The
operator approves it before phase A starts** (handoff §4 step 3). The
operator approved it on 2026-10-08 and answered §4's five decisions; the
answers are under "Operator decisions (2026-10-08)", and every phase below is
written to them.

**Where this plan and the spec differ, this plan wins** until the writer
applies the spec edits in §1. Programmers read §1 before they read the spec.

**Baseline at 38eb752** (re-measured for this plan):

| Measure | Value | Command |
|---|---|---|
| LuaJIT tests | 1357 passed, 0 failed | `.devtools/bin/check_lua.sh` |
| Lua files compiled | 365 | same |
| Python harness tests | 134 passed | `cd .devtools/bin && python3 -m pytest -q` |
| `tests/events_test.lua` | 27 tests | `luajit tests/events_test.lua` |
| Files the server sends clients | 191 | research §2 |
| `E.Define` calls | 30 lines in 10 files (29 events plus `client_ready`) | `grep -rn 'Define("' addon --include='*.lua'` |
| `WETSAND.BroadcastSound(ToOthers)` calls | 19, plus 2 definitions and 2 uses through the Wheel's port (the handoff's 23) | §D |
| Boss forwarder `me:FireGameEvent(` calls | **13 in 3 files** (merasmus 7, eyeball_boss 4, headless_hatman 2) | `grep -rc 'me:FireGameEvent(' addon/gamemodes/sandcastle/gamemode/foundation` |

The scholar counted 16 forwarder calls in 6 files. The other three hits it
counted (`npc/halloween_boss.lua:28`, `payload/race.lua:21`,
`rounds/payload.lua:16`) are comments that cite TF2's
`FireGameEvent`. `halloween_boss.lua:52` is the port's `METHODS` entry.

---

## 0. Before phase A (the director)

1. **Commit the research inputs to main.** `docs/game-events-v2-research.md`,
   `.devtools/bin/gev2/`, `.devtools/bin/gev2_probe.py` and
   `.devtools/bin/gmod_lua_cache.py` are untracked at 38eb752. A worktree
   made from main won't have them, and phase A's live probes reuse
   `gev2_probe.py`. Commit them in one signed commit, together with this plan
   once it's approved.
2. **The operator's answers to §4:** done on 2026-10-08, and recorded in
   the next section.

---

## Operator decisions (2026-10-08)

The operator answered the five decisions §4 asked. Three differ from the
plan's defaults. Nothing in this plan waits on the operator any more.

| # | Decision | Answer | The default? | Where it lands |
|---|---|---|---|---|
| 1 | Servers with `sv_allowcslua 1` | **Ignore it.** No report and no refusal: the library treats such a server like any other, and never reads the convar. | No (the default was to report once) | §1 row 2, A.4, A.6 item 12 |
| 2 | A client for T1 to T5 | **Yes, unattended.** The GMod client runs in the CrossOver bottle **"Team Fortress 2"**, because that bottle has the right Wine settings. The dedicated server still runs only in "Steam", through `srcds.py`. The exception covers only that GMod client, for T1 to T5; no server and no other process ever runs in that bottle (handoff §5 still holds for everything else). T1 to T5 are required phase-E criteria, and they confirm detection. | No (the default was no client) | "Live runs", §3, A.1, A.5, A.6 items 11, 13 to 15, E, §5 |
| 3 | Stop events on a stale file, or report it? | **Report only,** in the client's console and chat (and the server's log). `critical` is built but unused. | Yes | §1, A.2, A.4, A.6 item 7, C.1, C.3 item 10, E.1 |
| 4 | The events file | **Build** the generator, the pre-commit hook and the staleness test, in C. | Yes | C, as written |
| 5 | Phase D's scope | **Also move** `WETSAND.Announce`'s server-built text (the `announcement` event) and `gameplay_chat` to client listeners. | No (the default was to leave them) | D.1, D.2, D.3 items 7 to 9 |

**The architect's calls that follow from these** (technical; they are
listed again under "Judgment calls" at the end):

- **The convar `wetsand_events_check` is dropped.** With report only, its
  values 0 (off) and 2 (stop) have no use. The check is cheap (at most 1 ms
  a tick, plus one read of the sent files per map), and stopping isn't
  wanted. So the check always runs and only reports, and A adds no convar.
  - `code_stale` loses its `stop` field.
  - The client's answer is renamed from `code_stopped` to `code_touched`,
    because nothing stops.
  - The stop rules (`foundation/events/stops.lua`) and the `critical` option
    are still built and unit-tested, but no runtime code calls
    `Stops.Blocks`.
  - Turning stopping on later would be a new decision and a small adapter
    change, not a setting.
- **T1, T2 and T4 run early in A, as the gate for detection** (A.6 items 11
  and 14). They run unattended while the programmer builds A.1 to A.3.
  - T1 decides whether detection's premise holds, and T2 decides
    `SERVED_TEXT`, both before `drift.lua` is written. In E they would come
    after B to D had been built on a detection that might be wrong.
  - T4's client path form becomes a `Paths.Key` test in A, not a late fix.
  - None of the three needs the v2 library, only the client tools and
    probes.
  - **T3** runs once A is merged (A.6 item 15), because it tests A's codec
    over real `net`.
  - **In E, all five run again on the finished main** (E.3 item 4). That
    run confirms detection end to end, with a real client and a real stale
    file, and T5 sets `UNRELIABLE_MAX_BYTES`.
- **The two bottles share one GMod install.** The "Steam" bottle's
  `GarrysMod` folder is a symlink into the "Team Fortress 2" bottle's, so the
  client and the server read the same `garrysmod/`: `addons/sandcastle` (the
  symlink to this repo), `data/`, `cache/lua/` and `console.log`. That
  changes how T1 is staged (§3), and it means the client must never use
  `-condebug`, whose `console.log` the server writes.
- **D's counts were re-measured at main 29a6070** (D.3). `BroadcastSound`
  is unchanged (19 calls, of which 10 stay), and so are the text sites (23,
  of which 17 stay). `WETSAND.Announce` has 2 callers, not the 3 that §4
  said.

---

## 1. Spec changes adopted

The scholar's 14 required changes are adopted or adopted with a
modification. None is rejected. The writer applies the edits in the last
column to `docs/game-events-v2.md` when it starts work (after C lands). Until
then, this table is the spec.

| # | Scholar's change | Verdict | Reason, and the spec edit |
|---|---|---|---|
| 1 | §4 "What is compared": the server keeps references and compares them with what it now serves | **Adopted, modified** | The server keeps two references per sent file: the text **sent** (hashed by the `AddCSLuaFile` wrapper at send) and, for files it runs, the text **run** (read with `file.Read` just before `CompileFile` in `WETSAND.require` and `FeatureFiles:Run`). It does not switch to `CompileString`, which would change every chunk name and error path. What "now serves" means is the constant `SERVED_TEXT`, which T2 settles (§3); the default is `SERVED_DISK`. Edit: replace §4's first bullet with the scholar's wording plus these two sentences. |
| 2 | §4 threat sentence: shadowing happens on the server; name `sv_allowcslua 1` | **Adopted** | The operator chose to ignore `sv_allowcslua 1` (decision 1): no report and no refusal. Edit: rewrite the paragraph under "## 4". Shadowing happens on the server. With `sv_allowcslua 1` a client may run a local copy the check can't see, and the library treats such a server like any other. |
| 3 | §4 "When": the triggers are client ready, `feature_load` on a client, and a deduplicated gamemode refresh | **Adopted, modified** | A background scanner keeps the current hashes fresh within a per-tick budget, and the three triggers only *read* its results. That way no trigger reads files. An entity's refresh also takes a fresh reference for that entity, because its file reruns. Edit: replace the "When" bullet, and say `CompileFile`d files never rerun on refresh. |
| 4 | §4 file set: 191 files from the wrapper, fixed at start-up, no late sends | **Adopted, modified** | The adapter installs the wrapper once, before `init.lua`'s first `AddCSLuaFile`. To make that possible, `init.lua` includes `shared.lua` before its two `AddCSLuaFile` lines. A late call for a path not already sent is our error, `late_send`, which is logged. A repeat call for a path already sent (a refresh) is allowed. Edit: name the set and the rule. |
| 5 | §4 stop rules as a pure function of the stale set | **Adopted** | `foundation/events/stops.lua`. Edit: restate the rules as a function, independent of detection. |
| 6 | §4 cost: never stall a tick; no full reread at join | **Adopted** | The scanner probes at most `FILES_PER_TICK` files per tick. It screens by `file.Time` if phase A's measurement shows that is cheap and changes on save; otherwise it reads in turn. Start-up still reads every sent file once (126–163 ms, once per map). Edit: add the rule. |
| 7 | §4 attribution: match the path suffix; reject tail calls; say which feature an `entities/` site has | **Adopted** | The key is the path after `<folder>/gamemode/` or `<folder>/entities/`, giving `gamemode/...` or `entities/...`. `features/<name>/` keys belong to that feature, and every other key of ours is always loaded, entities included. Phase B moves every boss site out of `entities/` anyway. Edit: add the three rules. |
| 8 | §1 no wrapper forwards a name to `Fire`; migrate the boss forwarder | **Adopted, extended** | The count is corrected to 13 calls in 3 files (see the baseline). The rule extends to `Listen`: its name is a literal, and its listener is a function literal, so the field check can read it. The npc view's loop over `BossEvents.NAMES` goes. Edit: add both rules to §1's site rules and to the scan's list. |
| 9 | §2 values rewritten | **Adopted** | A record's keys are strings of at most 255 bytes. Tables with a metatable (`Color`) are `bad_fields`; send `r, g, b`. Edit: replace §2's "Values" bullet. |
| 10 | §3 tag table revised | **Adopted, modified** | Strings get a length prefix plus `WriteData`: 16 bits of length for values and 8 for keys. The int width is folded into the tag (`int8`, `int16`, `int32` are three tags), so there is no separate width tag. The full table is §A.3. Edit: replace §3's table with §A.3's. |
| 11 | §3 `too_large`: exact size, the 65,533-byte cap, an unreliable cap, and the ready burst | **Adopted, modified** | `UNRELIABLE_MAX_BYTES = 1200` is provisional, a named constant set by measurement (T5). The ready burst is several `Fire`s, so it isn't raised. Instead, the adapter counts the bytes sent to one player in one tick and logs our error `ready_burst` past `READY_BURST_MAX_BYTES = 131072`, half the 256 KB reliable buffer. Edit: add both. |
| 12 | §1/§3 order: validate and size before local dispatch, always | **Adopted** | A client-only event is validated but not sized, because it is never encoded. Edit: rewrite §1's "`Fire` runs the listeners…" paragraph. |
| 13 | §2 decoding a client's message: accept and rate by id first, then bounded decoding | **Adopted** | The refusal is `malformed`. It is the client's fault: dropped, and logged once per player per reason. Edit: add it under "Clients to the server". |
| 14 | §6 step 3 tests extended | **Adopted, extended** | The list is §A's tests. It adds `""` written without a zero-length `WriteData`, 255 against 256 keys, the depth cap, and 65,535 against 65,536 list items. The rewrite of `tests/events_test.lua` moves from step 3 to phase A (see the edits below). Edit: point §6 at this plan. |

**Further spec edits this plan makes** (technical calls; the writer applies
them too):

- **§2 `Fire`'s third argument is `options`** (`to`, `unreliable`,
  `critical`). Phase A rewrites every call that passes recipients today.
- **The client never hears the rates.** The accepted list goes to clients
  as names only, in the library event `events_accepted`. The rates are the
  server's business.
- **§4's protocol becomes three library events,** each with its one literal
  site in the adapter:
  - `code_stale { files }`: server to one client;
  - `code_touched { events }`: client to server, accepted. These are the
    events the stale files touch on that client; nothing stops;
  - `events_accepted { names }`: server to clients.

  The spec's `code_mismatch` is dropped, because the client no longer
  compares anything.
- **The check only reports** (operator decision 3), and no convar sets it:
  it always runs, and it never stops an event.
  - §4's "On a mismatch, only those events stop" and "Critical events stop
    their feature" become the definition of the stop rules: a pure model,
    built and tested, which no runtime code calls.
  - The error line reads as in A.4.
- **§5's generator is written in Lua,** as `.devtools/bin/gen_events_res.lua`,
  run by `luajit`. It shares one scanner, `.devtools/bin/events_scan.lua`,
  with the tests, which is what "the same scan" requires. The spec named a
  `.py` file.
- **§6's order changes:**
  - step 1 (A) replaces the v1 registry and rewrites `tests/events_test.lua`
    in the same commit, so that the test total never drops;
  - step 3 (C) removes only the `Define` and type-constructor shims, and
    builds the events file, the hook and the staleness test;
  - `Request` goes in A, since its only caller is the library's own
    `client_ready`.

---

## Rules for every phase

**Per-commit checks.** All of these must pass before each commit. The
evaluator reruns them on the branch.

```sh
.devtools/bin/check_lua.sh                      # exit 0; "TOTAL N passed, 0 failed"
python3 .devtools/bin/check_names.py            # exit 0
(cd .devtools/bin && python3 -m pytest -q)      # when any .devtools/bin/*.py changed; >= 134 passed
.devtools/bin/check_totals.sh main              # (from A's first commit) exit 0: no commit's TOTAL below its parent's
git log --format='%G?' main..HEAD | sort -u     # prints only G
git log --format=%B main..HEAD | grep -ciE 'co-authored-by|claude'   # prints 0
git status --short                              # empty when reporting
```

Commit with `git -c gpg.program=gpg-loopback commit -m "..."`. Keep commits
small, with no attribution and no push.

**The test total never drops, commit by commit.** A commit that deletes
tests along with the code they test must add at least as many in the same
commit. Phase A's switch commit is the one place this bites.
`check_totals.sh` enforces it.

**Code style** (load the `lua` skill):

- **Models in `foundation/` are pure `module(...)` files.** Each phase's new
  model gets its LuaJIT tests written first and seen failing. "Pure" is
  checked by `grep -nE '\b(net|util|file|hook|timer|player|ents|game|concommand|GetConVar|CurTime|SysTime|IsValid|Entity)\b[.(]' <file>`,
  which prints nothing. The models' I/O goes through a `host` table or
  injected functions.
- **Controllers coordinate, entities are thin bindings, clients present.**
  The adapter (`wetsand/sh_events.lua`) only wires `net`, players and hooks
  to the models.
- **Constants are named.** Multi-field tables have one field per line.
- **No `TF2` or `tf2` in our identifiers** (`check_names.py`).
- **No ENT function shares a name with an engine metatable method.** Check
  the wiki's Entity, NextBot and Player method lists.
- **Lazy loading stays:** no always-loaded file holds one mode's content.
  The event library itself is generic, so it is always loaded.

**Names:**

- New console names go through `.devtools/bin/check_engine_names.sh NAME...`,
  which must print `free`. It only reads files.
- New convars are listed in `addon/cfg/sandcastle_defaults.cfg` at their
  default; `tests/cfg_defaults_test.lua` checks this.
- Meta and debug names use `wetsand_`.
- New event names reuse TF2's event and field names where TF2 has the event.
  Read them from the mounted TF2's `tf/resource/modevents.res`, read-only.
- Library-internal events have plain names, like `client_ready` and
  `feature_load`.

**Live runs.**

- Run servers only through `.devtools/bin/srcds.py` and
  `.devtools/bin/ingame_tests.py`, in the bottle "Steam".
- **The bottle "Team Fortress 2" has one exception** (operator decision 2):
  the GMod client for T1 to T5. Only `.devtools/bin/gmod_client.py` launches
  or closes it, with §3's safeguards. No server and no other process ever
  runs there, and nothing else launches or signals anything in that
  bottle.
- The server loads main through the `sandcastle` symlink. A phase's live
  criteria therefore run on main after the director merges it. Phase A's
  probes are the exception: they may run earlier by copying the modules they
  test into `garrysmod/data/wetsand_tests/`, as `gev2_probe.py` does.
- Stop the server when done (`python3 .devtools/bin/srcds.py stop`).

---

## Phase A: the library behind today's API

**Goal.** Build the whole v2 library: the codec with its exact size model,
validation before dispatch, a client's `Fire`, `Accept` and the rate limit,
attribution by path suffix, the `AddCSLuaFile` wrapper, the server-side drift
check, and the stop rules. Every feature keeps working unchanged.

- `Define` and the type constructors become inert shims that only phase B's
  migration still calls.
- The site scanner and its tree test land, with a list of unmigrated files
  that B empties.
- The client tools for T1 to T5 land first (§3): `gmod_client.py`,
  `gev2_marker.py`, and `gev2_probe.py`'s client mode.

**One programmer, plus the researcher for the early client session** (§3),
which is the second agent.

1. After `check_totals.sh`, the programmer's first deliverables are the
   client tools and their tests, plus `srcds.py --no-lua-refresh`.
2. Once they're committed on the A branch, the director starts the
   researcher on T1, T2 and T4. The researcher runs the A worktree's
   scripts against main, because the server loads main.
3. Meanwhile the programmer builds A.1 to A.3 and the stop rules.
   Detection waits for T1 and T2 (A.6 item 11).

### A.1 Files

| File | Change |
|---|---|
| `addon/gamemodes/sandcastle/gamemode/foundation/events.lua` | **Replaced:** the v2 core facade (pure), composed of the modules below. The v1 `Registry`, types and schemas go. `Crc32` moves to `codec.lua`. |
| `foundation/events/codec.lua` | New. Validation, the key table, the exact bit-size model, encode, and bounded decode. |
| `foundation/events/rates.lua` | New. The accepted names and the per-player, per-event token bucket (moved from v1's `Admit`). |
| `foundation/events/paths.lua` | New. Source path to key, key to feature and kind, and `AddCSLuaFile` argument resolution. |
| `foundation/events/drift.lua` | New. The sent and run references, observed hashes, the scanner's state, and the stale query. |
| `foundation/events/stops.lua` | New. The stop rules. |
| `gamemode/wetsand/sh_events.lua` | **Rewritten.** The adapter: `net`, recipients (`to`), readiness, the wrapper's install, the scanner's `Think`, reports, and the library events. It has no convar (decision 3). It keeps inert `Define` and type constructors until C. `Request` goes. |
| `gamemode/wetsand/sh_core.lua` | On the server, `WETSAND.require` and `FeatureFiles:Run` read the text and record the run hash for sent files. Files compiled before the adapter exists are queued, and recorded when it starts. |
| `gamemode/init.lua` | `include("shared.lua")` moves above the two `AddCSLuaFile` lines, so the wrapper sees every send. |
| Every `Fire` call with a third argument (`sh_core.lua:82`, `features/nbdebug/sv.lua` ×6 and any others the scan finds) | The argument becomes `{ to = ... }`. Behaviour is unchanged. |
| The three sites whose event had a `Default` (`features/capture/sv.lua` `cappers`, `wetsand/sv_world.lua` `others` and `team`) | Each sends the value the default supplied, or the listener treats `nil` the same way. Behaviour is unchanged. |
| `.devtools/bin/gmod_client.py`, `test_gmod_client.py` | New, A's second commit. It launches and closes the GMod client in the bottle "Team Fortress 2" for T1 to T5. §3's safeguards are its tested behaviour (A.5). |
| `.devtools/bin/gev2_marker.py`, `test_gev2_marker.py` | New. It sets and restores the uncommitted marker lines that T1, T2 and E's client check put in an addon file (§3). |
| `.devtools/bin/gev2_probe.py` | Gains `run --client NAME...`: the probe runs on every connected client (§3). Its output lands in `.devtools/artifacts/gev2-research/client/`. |
| `.devtools/bin/srcds.py`, `test_srcds.py` | `start` gains `--no-lua-refresh`, which adds `-disableluarefresh` (T1). Nothing else changes, and it still refuses every bottle but "Steam". |
| `.devtools/bin/gev2/client_t1.lua`, `client_t2.lua`, `client_t4.lua` | New client probes, written by the researcher for the early session. `client_t3.lua` is the programmer's, for A.6 item 15. |
| `.devtools/bin/events_scan.lua` | New. The Lua site scanner (tokenizer-aware: strings and comments are never calls), used by the tests now and the generator in C. |
| `tests/events_unmigrated.lua` | New. The ratchet: `return { b1 = { ...paths }, b2 = { ...paths } }`, the files exempt from the site rules until B migrates them. The two blocks sit at least 5 lines apart, so B1's and B2's edits merge cleanly. |
| `.devtools/bin/check_totals.sh BASE` | New, and A's first commit. For each commit in `BASE..HEAD`, it exports the tree (`git archive`) to a temp dir, runs its `check_lua.sh`, and prints `sha TOTAL subject`. It exits 1 if any commit's total is below its parent's. |
| `.devtools/bin/expected_sent_files.sh` | New. Prints the sorted keys the server should send, from the tree: `gamemode/shared.lua`, `gamemode/cl_init.lua`, every `gamemode/foundation/**/*.lua`, `gamemode/features/*/{sh,cl}.lua`, `gamemode/wetsand/{sh_,cl_}*.lua`, and every `entities/{entities,weapons}/*.lua` with a line starting `AddCSLuaFile()`. |
| `.devtools/bin/gev2/events_size.lua`, `events_sent.lua`, `events_scan_cost.lua` | New probes, run by `gev2_probe.py` (A.6). |

### A.2 Interfaces

**Public API** (`WETSAND.Events`, both realms unless marked):

```lua
Events.Fire(name, fields, options)  -- options: nil or { to = nil|team|Player|{Player...}|Vector, unreliable = bool, critical = bool }
Events.Listen(name, id, fn)         -- fn(fields) ; on the server, for a client's event, fn(fields, ply)
Events.Ignore(name, id)
Events.Accept(name, rate)           -- server only; rate = { count = whole >= 1, seconds = number > 0 }
-- until phase C only: Events.Define(...) and the type constructors exist and do nothing
```

**`foundation.events` (the facade, pure).**

```lua
Events.New(host) -> Library
-- host = {
--   realm = "server" | "client",
--   folder = "sandcastle",           -- GM.FolderName
--   values = <the codec's host value interface, below>,
--   hash = function(text) -> string, -- util.CRC in game, any stable function in tests
-- }
Library:Fire(name, fields, options, source) -> Outgoing | nil
-- source: debug.getinfo(2, "S").source, taken by the adapter.
-- It validates, sizes and records attribution, then dispatches locally.
-- It returns { id, plan, unreliable, to } when the event leaves the realm, else nil.
-- Raises bad_fields, too_large, bad_options or id_collision before any listener runs.
Library:Listen(name, id, fn, source)
Library:Ignore(name, id)
Library:Accept(name, rate)                 -- server; raises bad_accept
Library:SetAccepted(names)                 -- client, from events_accepted
Library:Write(outgoing, writer)            -- writer: net-like, called with a dot
Library:ReceiveFromClient(reader, sender, now) -> nil | refusal
-- server: id -> accepted? -> rate -> bounded decode -> dispatch(fields, sender).
-- A refusal is a named not_accepted, rate_limited or malformed, never raised.
Library:ReceiveFromServer(reader)
-- client: an id with no listener is ignored. Decoding failure raises
-- malformed, because a bad message from the server is our bug.
Library:Sites() -> { [name] = { key, feature, critical } }  -- attribution, for stops and the print commands
Library:ListenKeys() -> { [name] = { [key] = true } }
```

**`foundation.events.codec`.**

```lua
Codec.Id(name) -> integer            -- Crc32(name) % 2^ID_BITS
Codec.Crc32(s) -> integer
Codec.Plan(fields, values) -> plan   -- raises bad_fields; plan.bits = the payload's exact bit count, header excluded
Codec.Bytes(plan) -> integer         -- HEADER_BYTES + ceil((ID_BITS + plan.bits) / 8): what net.BytesWritten() will read
Codec.CheckSize(plan, unreliable)    -- raises too_large: Bytes > MESSAGE_MAX_BYTES, or > UNRELIABLE_MAX_BYTES when unreliable
Codec.Write(id, plan, writer, values)
Codec.ReadId(reader) -> integer
Codec.ReadFields(reader, values) -> fields | nil, refusal   -- bounded; never raises
-- values (the host value interface):
-- { kind(v) -> "entity"|"vector"|"angle"|nil, index(e) -> integer|nil (nil for NULL),
--   entity(i), null(), xyz(v) -> x, y, z, vector(x, y, z), angle(p, y, r) }
-- reader/writer: net's Write/ReadUInt, Bool... plus WriteData/ReadData, WriteFloat/ReadFloat,
--   WriteDouble/ReadDouble, and BytesLeft()
```

**`foundation.events.rates`.**

```lua
Rates.New() -> Rates
Rates:Accept(name, rate)             -- raises bad_accept
Rates:NameOf(id) -> name | nil
Rates:Admit(sender, id, now) -> boolean
Rates:Names() -> { name... }         -- sorted, for events_accepted
```

**`foundation.events.paths`.**

```lua
Paths.Key(source, folder) -> key | nil      -- "gamemode/features/capture/cl.lua", "entities/entities/merasmus.lua"; nil if not ours
Paths.FeatureOf(key) -> name | nil          -- nil: always loaded
Paths.KindOf(key) -> KIND_INCLUDED | KIND_COMPILED | KIND_ENTITY
Paths.Resolve(callerSource, arg, folder) -> key | nil   -- AddCSLuaFile(arg) as called from callerSource
Paths.LuaPath(key, folder) -> "sandcastle/gamemode/..." -- for file.Read(..., "LUA")
```

**`foundation.events.drift`.**

```lua
Drift.New(served) -> Drift           -- served: SERVED_DISK (default) | SERVED_SENT, settled by T2
Drift:Sent(key, kind, hash, time, startedUp)  -- raises late_send for a new key once startedUp
Drift:Ran(key, hash)
Drift:Observe(key, hash, time)
Drift:NeedsRead(key, time) -> boolean        -- the file.Time screen
Drift:Stale(keys) -> { { key = ..., reason = ... } ... }
Scanner.New(keys, perTick) -> Scanner
Scanner:Step() -> { key... }         -- at most perTick keys per call, round robin
```

**`foundation.events.stops`.**

```lua
Stops.Touched(staleKeys, sites, listenKeys, realm) -> { [name] = true }
-- On the client: the events with a listener in a stale key, plus the events
-- whose client Fire site is in one.
Stops.Blocks(touched, staleKeys, sites, name) -> boolean
-- name is touched; or a touched event is critical and shares name's feature;
-- or a touched critical event's stale key is always loaded. Built and
-- unit-tested, but no runtime code calls it (operator decision 3). If
-- stopping is ever wanted, it is evaluated at send and at receive with the
-- current sites, so a critical site that first runs later still counts.
```

**Named errors.** Each is a table `{ kind, message }` that prints as
`kind: message`:

- our bugs, raised: `bad_fields`, `too_large`, `bad_options`, `bad_accept`,
  `id_collision`, `late_send`;
- our bugs, logged: `ready_burst`;
- the client's fault, refused: `not_accepted`, `rate_limited`, `malformed`;
- reported, never raised: `stale_code`.

### A.3 The wire (replaces spec §3's table)

A message is the net header (3 bytes), then:

1. the id, 24 bits;
2. the key count, 8 bits, then for each key an 8-bit length and its bytes;
3. the top-level fields as an untagged record body: an 8-bit count, then for
   each field an 8-bit key index and a tagged value.

A tag is 4 bits.

| Tag | Payload | Bits after the tag |
|---|---|---|
| `false`, `true` | none | 0 |
| `int8`, `int16`, `int32` | zig-zag, unsigned; the narrowest that fits; whole numbers in [-2^31, 2^31-1] | 8 / 16 / 32 |
| `double` | `WriteDouble`, for every other number (`inf`, `NaN`, ±2^31 and beyond, fractions) | 64 |
| `string` | 16-bit length, then `WriteData` (skipped when the length is 0) | 16 + 8·len |
| `entity` | its index (the world is 0) | 13 |
| `entity_null` | none: `NULL`, kept apart from the world | 0 |
| `vector`, `angle` | three `WriteFloat`s, exact | 96 |
| `list` | 16-bit count, then each item tagged; `{}` is an empty list | 16 + Σ |
| `record` | 8-bit count, then key index (8) and tagged value per field | 8 + Σ (8 + v) |

Named constants:

| Constant | Value |
|---|---|
| `TAG_BITS` | 4 |
| `ID_BITS` | 24 |
| `KEY_COUNT_BITS`, `KEY_INDEX_BITS`, `KEY_LENGTH_BITS`, `RECORD_COUNT_BITS` | 8 each |
| `LIST_COUNT_BITS`, `STRING_LENGTH_BITS` | 16 each |
| `ENTITY_BITS` | 13 |
| `MAX_DEPTH` | 16 |
| `HEADER_BYTES` | 3 |
| `MESSAGE_MAX_BYTES` | 65536 (`net.BytesWritten()`, header included) |
| `UNRELIABLE_MAX_BYTES` | 1200 (provisional; T5) |
| `READY_BURST_MAX_BYTES` | 131072 |

These are `bad_fields`:

- a function, a cycle, or other userdata;
- a table with a metatable;
- non-string keys, mixed list and record keys, or a list whose keys aren't
  exactly 1..n;
- a key over 255 bytes, or more than 255 distinct keys;
- a list over 65,535 items, or nesting over `MAX_DEPTH`.

A string over 65,535 bytes is `too_large`.

**Decoding a client's message, in this order:**

1. read the id;
2. `Rates:NameOf(id)`, else `not_accepted`;
3. `Rates:Admit`, else `rate_limited`;
4. decode, refusing with `malformed` on any of:
   - a count or length that can't fit in the `BytesLeft()` that remain (each
     item costs at least `TAG_BITS`);
   - depth over `MAX_DEPTH`;
   - an unknown tag;
   - a key index at or past the key count.

### A.4 Detection and the stop protocol

- **The wrapper.** The adapter's server block replaces the global
  `AddCSLuaFile` once (kept in `WETSAND.SentFiles` across refreshes), always
  calling the previous function. Each call:
  1. resolves its argument with `Paths.Resolve` against
     `debug.getinfo(2, "S").source`, skipping files that aren't ours;
  2. reads the text through `LUA`;
  3. records `Drift:Sent` with the kind's rule:
     - `KIND_COMPILED` keeps its first reference, because nothing reruns it;
     - `KIND_INCLUDED` and `KIND_ENTITY` take the new one, because their
        file reran.

  "Started up" is `InitPostEntity` on the server. After it, a new key raises
  `late_send`; the adapter catches it and logs it as our error.
- **The scanner.** A server `Think` hook probes `FILES_PER_TICK` keys per
  tick (start at 2; tune from A.6's measurement), and `Drift:Observe`s each.
  If A.6 shows `file.Time` is cheap and changes on save, set
  `SCREEN_BY_TIME = true`. Otherwise every probe reads and hashes the file.
- **Triggers.** Each one asks `Drift:Stale` for its keys:
  - a player's `client_ready`: the entry files, `wetsand/`, `foundation/` and
    the entities;
  - `feature_load` to a player: that feature's client parts;
  - a gamemode refresh: `OnReloaded`, deduplicated to one handling per tick.
    It only re-takes references through the wrapper's reruns; connected
    clients reran the same included files.

  A non-empty result is fired to that player as `code_stale { files }`,
  and the server logs it.
- **The client** works out `Stops.Touched`. It reports once to its console
  and its chat, in this form:

  `network error: gamemode/features/capture/cl.lua differs from the server's; events it touches (not stopped): teamplay_capture_blocked`

  It stops nothing (operator decision 3), and it fires
  `code_touched { events }`.
- **The server** records each player's touched set and logs one line, in
  the same form with the player's name in front. It drops nothing. No
  runtime code calls `Stops.Blocks`, which stays a tested model in case
  stopping is ever wanted.
- **Client-only events** (client `Fire` and client `Listen`, never on the
  wire) are never stopped: both ends are the client's own code.
- **`sv_allowcslua` is ignored** (operator decision 1). The library never
  reads it, logs nothing about it, and refuses nothing. The check runs the
  same whatever its value.
- **Library events** and their one site each, all in `sh_events.lua`:

  | Event | Fired by | Accepted |
  |---|---|---|
  | `client_ready` | the client at `InitPostEntity` | 2 per 10 s; the client treats it as accepted before `events_accepted` arrives |
  | `events_accepted { names }` | the server: to a player on ready, and to all ready players when `Accept` runs after start-up | |
  | `code_stale { files }` | the server | |
  | `code_touched { events }` | the client | 4 per 10 s |

### A.5 Tests to write first

Write each file's tests first and watch them fail.

- Each listed name is an exact `T.test` name the evaluator greps for.
- More tests are welcome.
- The fake buffer in the tests counts bits per write as GMod does (research
  §4's table), exposes `BytesWritten()` and `BytesLeft()`, and errors on a
  read of the wrong kind or width.

`tests/events_codec_test.lua`:
- `an empty string and a string holding NUL round-trip exactly`
- `2^31-1 and -2^31 go as ints; 2^31 and -2^31-1 go as doubles`
- `inf, -inf and NaN go as doubles; -0 arrives as 0`
- `an int takes the narrowest of 8, 16 and 32 bits`
- `vectors and angles round-trip exactly, beyond 16384 too`
- `NULL and the world arrive apart`
- `{} arrives as {}`
- `the key table names each key once, however many records use it`
- `a list with a hole, non-string keys, mixed keys, a cycle, a function or a table with a metatable is bad_fields`
- `255 distinct keys fit; 256 is bad_fields`
- `65535 list items fit; 65536 is bad_fields`
- `nesting deeper than MAX_DEPTH is bad_fields`
- `the size model counts every bit the writer writes` (over a corpus of at least 20 events covering every tag; the plan's bits equal the fake buffer's)
- `an event at the reliable cap fits; one byte over is too_large`
- `an unreliable event over UNRELIABLE_MAX_BYTES is too_large`
- `a count larger than the bytes left is malformed`
- `a string length past the bytes left is malformed`
- `an unknown tag is malformed`
- `a key index past the key table is malformed`
- `nesting past MAX_DEPTH on the wire is malformed`

`tests/events_test.lua` (rewritten in the same commit that replaces the v1
core, with at least 27 tests):
- `CRC32 is the standard one (zlib's, GMod's util.CRC)` (kept)
- `an event's id is its name's CRC32 cut to 24 bits, the same in any realm and order`
- `two names with one id in a realm raise id_collision, naming both` (v1's `event_188781` / `event_326020` pair)
- `listeners run in the order added with the fields and what the adapter adds` (kept)
- `listening again under an id replaces that listener in its place; Ignore removes it` (kept)
- `a listener added during a dispatch counts from the next one`
- `Fire validates and sizes before any local listener runs`
- `Fire raises bad_fields with no listener and no recipient`
- `unknown options, to on a client, and a non-boolean critical are bad_options`
- `a client's Fire stays local unless the server accepted the event`
- `client_ready leaves a client before any accepted list arrives`
- `the server dispatches a client's accepted event with its sender`
- `a client's event the server did not accept is refused before its fields are read`
- `each player's sends are rate limited per event; the allowance refills with time` (v1's schedule, kept)
- `a malformed client message is refused as the client's fault and logged once per player`
- `an id with no listener is ignored on the client`
- `Fire records its site's key, feature and critical flag the first time it runs`
- `a rate is refused unless count is whole and at least 1 and seconds is above 0`
- `only the event adapter registers, starts or receives net messages` (kept; the adapter's two messages)

`tests/events_paths_test.lua`:
- `a source in the legacy addon folder, under gamemodes/, or LUA-relative gives the same key`
- `entities and weapons keep their entities/ key`
- `Sandbox's and GMod's own files are not ours`
- `a key under features/<name>/ belongs to that feature; every other key of ours is always loaded`
- `AddCSLuaFile resolves against the caller's folder, and no argument means the caller's own file`
- `wetsand/ and the entry files are included, foundation/ and features/ compiled, entities/ entities`
- `a source longer than short_src keeps resolves whole`

`tests/events_drift_test.lua`:
- `a file sent and run with the same text is not stale`
- `a compiled file whose text changes is stale, and stays stale after a gamemode refresh`
- `an included file sent again by a gamemode refresh takes the new text as its reference`
- `an entity sent again by its refresh takes the new text as its reference`
- `a module compiled after start-up from other text than was sent is stale`
- `under SERVED_SENT a change on disk alone is not stale`
- `the scanner probes at most its per-tick count and visits every file in turn`
- `with time screening a file whose time is unchanged is not read`
- `a new path sent after start-up is late_send; a path sent again is not`

`tests/events_stops_test.lua`:
- `a stale file stops the events it listens to and the events it fires, and nothing else`
- `a critical event touched by a stale file stops every event of its feature`
- `a critical event touched by a stale always-loaded file stops every event`
- `a critical site that first runs after the report still widens the stop`
- `an empty stale set stops nothing`
- `client-only events are never stopped`

`tests/events_scan_test.lua` (fixture strings, not the tree):
- `strings and comments that look like calls are not calls`
- `a Fire with a non-literal name is reported`
- `fields that are not a table literal are reported`
- `a second Fire site for one name is reported`
- `a listener reading a field its site does not send is reported`
- `return Events.Fire( and return Events.Listen( are reported`
- `a Listen with a non-literal name or a listener that is not a function literal is reported`
- `options other than a table literal of to, unreliable and critical are reported`
- `an alias of WETSAND.Events other than local Events is reported`
- `a Fire site with no comment directly above it, or a field line with no trailing comment, is reported`
- `an Accept with no Fire site is reported`
- `two names with one id are reported`

`tests/events_sites_test.lua` (the whole of `addon/`, minus the ratchet's
files):
- `every event has exactly one literal Fire site`
- `every listener reads only fields its event's site sends`
- `no Fire or Listen is tail-called`
- `no two event names share an id` (over Fire, Listen, Accept and the
  remaining `Define` names)
- `every Fire's options are a table literal of to, unreliable and critical`
  (ratchet ignored: A converts every call)
- `no file is exempt from the site rules except those the migration lists`
  (each ratchet entry exists and still breaks a rule)

`.devtools/bin/test_gmod_client.py` (pytest). The process table, the `lsof`
output, the launcher, the clock and the signal call are injected, so no test
starts or signals a real process:
- `test_refuses_while_tf2_runs` (any `tf_win64.exe`, `tf.exe` or `hl2.exe`,
  in any bottle)
- `test_refuses_while_a_gmod_client_runs` (`gmod.exe` or `gmod_win64.exe`)
- `test_refuses_without_steam_running_in_the_tf2_bottle`
- `test_refuses_while_its_own_client_still_runs`
- `test_has_no_way_to_choose_another_bottle`
- `test_launches_only_the_gmod_client`: exactly one launch, of
  `gmod_win64.exe` through the bottle's wine with
  `--bottle "Team Fortress 2"`, `+connect 127.0.0.1:<port>` and
  `+con_logfile` under `data/wetsand_tests/client/`, and never `-condebug`
- `test_records_the_one_new_client_pid`
- `test_stop_signals_only_the_launched_client`: with a wineserver, wine's
  services, `steam.exe`, `steamwebhelper.exe`, a `tf_win64.exe`, the wine
  launcher and a second `gmod_win64.exe` in the table, only the recorded PID
  is signalled
- `test_stop_leaves_a_reused_pid_alone`
- `test_stop_escalates_to_sigkill_on_the_same_pid_only`
- `test_the_watchdog_closes_the_client_when_the_operators_game_starts`
- `test_the_watchdog_closes_the_client_at_its_time_limit`
- `test_stop_reports_changed_cfg_files`

`.devtools/bin/test_gev2_marker.py`:
- `test_refuses_a_file_with_uncommitted_changes`
- `test_refuses_a_file_outside_addon`
- `test_refuses_a_second_set_before_restore`
- `test_restore_puts_back_the_exact_bytes`
- `test_restore_after_a_failed_run_leaves_the_file_clean`

`.devtools/bin/test_srcds.py` adds:
- `test_no_lua_refresh_adds_disableluarefresh`

### A.6 Acceptance criteria

1. The per-commit checks pass on every commit (`check_totals.sh main` exit
   0), and the final TOTAL is at least 1357 + the tests A adds.
2. Every test named in A.5 exists and passes:
   `grep -hoE 'T\.test\("[^"]+"' tests/events_*_test.lua` contains each one.
3. Purity: the grep under "Code style" prints nothing for
   `foundation/events.lua` and `foundation/events/*.lua`. Each starts with
   `module(...)` after its locals.
4. `grep -rnE '\.Request\(' addon --include='*.lua'` prints nothing.
5. `grep -c 'local Registry' addon/gamemodes/sandcastle/gamemode/foundation/events.lua`
   prints 0: the v1 core is gone.
6. `grep -n 'include("shared.lua")' addon/gamemodes/sandcastle/gamemode/init.lua`
   is line 1 or the first non-comment line, and comes above both
   `AddCSLuaFile` lines.
7. No convar, and nothing stops (operator decision 3):
   - `grep -rn 'wetsand_events_check' addon tests .devtools/bin` prints
     nothing (0 at 29a6070);
   - `git diff --quiet main -- addon/cfg/sandcastle_defaults.cfg` exits 0,
     and `luajit tests/cfg_defaults_test.lua` passes, because A adds no
     convar;
   - `grep -n 'Blocks' addon/gamemodes/sandcastle/gamemode/wetsand/sh_events.lua`
     prints nothing;
   - `grep -rn 'code_stopped' addon tests` prints nothing.
8. The ratchet: `luajit -e 'local u = dofile("tests/events_unmigrated.lua"); print(#u.b1, #u.b2)'`
   prints the B1 and B2 file counts of §B. Every file in it breaks a rule
   (that is the last sites test).
9. **Live probes** (srcds on koth_viaduct, then
   `python3 .devtools/bin/gev2_probe.py run events_size events_sent events_scan_cost`;
   outputs land in `.devtools/artifacts/gev2-research/live/`):
   - `events_size.txt`: for at least 20 events (every tag, one event at the
     cap and one a byte over), `Codec.Bytes(plan)` equals
     `net.BytesWritten()` after `Codec.Write`. The file ends
     `mismatches 0`, and the over-cap case reports `too_large` before any
     write.
   - `events_sent.txt`: the wrapper's keys. Then
     `diff <(.devtools/bin/expected_sent_files.sh) <(sed -n '/^keys$/,$p' .devtools/artifacts/gev2-research/live/events_sent.txt | tail -n +2)`
     prints nothing. That's 191 at 38eb752, plus A's new `foundation/`
     files.
   - `events_scan_cost.txt`:
     - the cost of `file.Time` over every sent key (total and per file);
     - whether `file.Time` changed after `touch` on a data-folder copy;
     - the scanner's worst tick over 600 ticks, which must be at most
       1.0 ms;
     - the `SCREEN_BY_TIME` and `FILES_PER_TICK` chosen.
10. **Post-merge smoke:**
    `python3 .devtools/bin/ingame_tests.py --maps koth_viaduct` exits 0, and
    the report shows 0 Lua errors.
11. The drift work starts only after T1 and T2 are recorded (item 14).
    That is A.4's detection: `drift.lua`, the wrapper, the scanner and the
    triggers.
    - If T1 fails, the architect re-plans A.4 with the operator before any
      of it is written (§3).
    - Only the detection waits. The stop rules, codec, rates and paths
      don't.
12. `sv_allowcslua` is ignored (operator decision 1):
    `grep -rn 'allowcslua' addon --include='*.lua'` prints nothing (0 at
    29a6070). No test asserts a report, because none is made.
13. The client tools pass their tests:
    `cd .devtools/bin && python3 -m pytest -q test_gmod_client.py test_gev2_marker.py test_srcds.py`
    passes. `grep -hoE 'def test_[a-z0-9_]+' test_gmod_client.py test_gev2_marker.py test_srcds.py`
    contains every name A.5 gives for them.
14. **The early client session** (§3: T1, T2 and T4), unattended:
    - the research file gains `## Client session` with each test's result,
      and the outputs are under `.devtools/artifacts/gev2-research/client/`;
    - `.devtools/artifacts/gev2-research/client/gmod_client.log` shows, for
      each launch, the preflight's findings, the one PID launched, and that
      PID (and only it) being closed;
    - after the session, no `gmod_win64.exe` runs
      (`ps -axo command= | grep -c '[g]mod_win64.exe'` prints 0), and
      `git status --short` on main is what it was before (the markers are
      restored);
    - `Drift.New`'s default `served` is the value T2 chose, with a comment
      citing the research section;
    - `tests/events_paths_test.lua` has T4's client form as a case, if it
      differs from the three forms.
15. **T3, after the merge:**
    1. start the server with `srcds.py start --map koth_viaduct`, and the
       client with `gmod_client.py start`;
    2. `python3 .devtools/bin/gev2_probe.py run --client client_t3` writes
       `client/client_t3.txt`, which ends `mismatches 0` for both
       directions;
    3. the client's log has 0 Lua errors (the command in E.3 item 4);
    4. `gmod_client.py stop`, then `srcds.py stop`.

---

## Phase B: migrating each feature

**Goal.**

- Every event has its one literal `Fire` site, with its comment block and
  trailing field comments.
- No `E.Define` remains.
- The boss forwarder is gone.
- Every `Listen` is literal.
- The ratchet is empty.

**Two programmers may run at once, on disjoint files** (the two-agent limit;
the writer does not start in B). Each B programmer works in its own
worktree off main after A merges. The director merges B1 and B2 one after
the other, and the architect evaluates B once both are in.

### B.1 Scope

**B1: always-loaded, rounds, capture and gamemode** (9 events).

| Files | Events | What changes |
|---|---|---|
| `wetsand/sh_core.lua` | `feature_load` | Its two sites (`:55`, `:82`) become one function holding the site, `FeatureFiles:TellClients(names, to)` |
| `wetsand/sh_announcer.lua`, `wetsand/sv_world.lua` | `teamplay_broadcast_audio`, `announcement` | `BroadcastSound` and `BroadcastSoundToOthers` call one local function holding the single site; the two `Define`s go |
| `wetsand/sh_gameplay.lua`, `features/gamemode/sv.lua` | `gameplay_chat`, `gameplay_transition_cancelled` | `Define`s go; sites documented |
| `features/capture/{sh,sv,cl}.lua` | `teamplay_point_captured`, `teamplay_capture_blocked` | same |
| `features/rounds/{sh,sv,cl}.lua` | `teamplay_timer_time_added` | same |
| `wetsand/{sh,sv,cl}_npc_ragdolls.lua` | `npc_ragdoll_create` | same |

**B2: the npc feature and the debug overlays** (20 events).

| Files | Events | What changes |
|---|---|---|
| `foundation/npc/halloween_boss.lua` (`METHODS`), `foundation/npc/{merasmus,eyeball_boss,headless_hatman}.lua`, `entities/entities/halloween_base_boss.lua`, `features/npc/{sh,sv,cl}.lua`, `foundation/npc/boss_events.lua` | the 12 boss events | See "The boss port" below. |
| `features/nbdebug/{sh,sv,cl}.lua`, `features/aiwar/sv.lua` (the `aiwar_debug` site only) | 6 `nb_debug_*`, `aiwar_debug` | `Define`s go; sites documented; `Optional` fields simply left out when absent |
| `wetsand/sh_nodegraph.lua`, `features/nodegraph/sv.lua` | `nodegraph_debug` | same |
| `tests/{merasmus,eyeball_boss,headless_hatman,halloween_boss,boss_events,nbdebug_contract}_test.lua` and the fakes they use | | Updated to the new port, with per-file counts kept (B.3) |

**The boss port (a technical call; see the end of this plan).**

- **The port.** `METHODS` loses `"FireGameEvent"` and gains one method per
  event:
  - `PumpkinLordSummoned()`, `PumpkinLordKilled()`;
  - `EyeballBossSummoned(level)`, `EyeballBossKilled(level)`,
    `EyeballBossEscapeImminent(level, seconds)`,
    `EyeballBossEscaped(level)`;
  - `MerasmusSummoned(level)`, `MerasmusKilled(level)`,
    `MerasmusEscapeWarning(level, seconds)`, `MerasmusEscaped(level)`,
    `MerasmusKiller(player, level)`;
  - `HalloweenBombHead(player, duration)`, which is called from both bomb
    head sites and so keeps one `Fire` site.
- **The binding.** `halloween_base_boss.lua` implements each method by
  calling the npc controller (`WETSAND.Feature("npc"):<Method>(...)`).
- **The sites.** `features/npc/sv.lua` holds each literal `Fire` site, so
  the events belong to the `npc` feature, beside the view that hears them.
- **The view.** `features/npc/cl.lua` drops the loop over `BossEvents.NAMES`
  for 11 literal `Listen`s (plus the bomb head's). Each passes its literal
  name to `View:PlayBossCue`.
- **The names list.** `BossEvents.NAMES` goes if nothing else uses it;
  `Cue` keeps its name-keyed table.

### B.2 Tests to write first

- **B2, the bosses.** Change the boss model tests to expect the new port
  calls (for example, Merasmus's summon calls `MerasmusSummoned(level)`
  once), and watch them fail before changing the models.
- **B2, the contract test.**
  `tests/nbdebug_contract_test.lua`'s test
  `every game event they fire is defined in the feature's shared part, for both realms`
  becomes `every game event they fire has its one literal site in the controllers`.
  The count stays at 4.
- **B2, the port test.** `tests/halloween_boss_test.lua`'s port test is
  updated for the new `METHODS`, and checks that no port method shares a
  name with an engine method on the wiki's lists.
- **Both programmers.** For each file taken off the ratchet, run
  `luajit tests/events_sites_test.lua` first and see it fail on that file.

### B.3 Acceptance criteria

1. The per-commit checks pass on every commit of B1 and of B2.
2. `grep -rnE '\.Define\(' addon --include='*.lua' | grep -v 'wetsand/sh_events.lua'`
   prints nothing.
3. `grep -rnE '[^:]:FireGameEvent\(|[.:]FireGameEvent *=|function [A-Za-z_.:]*FireGameEvent|"FireGameEvent"' addon tests`
   prints nothing. Only comments citing TF2's `::FireGameEvent` remain.
4. `luajit -e 'local u = dofile("tests/events_unmigrated.lua"); print(#u.b1 + #u.b2)'`
   prints `0`.
5. `luajit tests/events_sites_test.lua` passes, now over every file.
6. Per-file test counts are at least the baseline:
   - merasmus 45, eyeball_boss 44, headless_hatman 25, halloween_boss 17,
     boss_events 12, nbdebug_contract 4;
   - capture_points 43, rounds_game 28, gameplay 3, gamemode 20,
     npc_ragdoll 7, nodegraph 8.

   Command:
   `for t in merasmus eyeball_boss headless_hatman halloween_boss boss_events nbdebug_contract capture_points rounds_game gameplay gamemode npc_ragdoll nodegraph; do printf "$t "; luajit tests/${t}_test.lua | tail -1; done`.
7. `grep -rn 'BossEvents.NAMES' addon --include='*.lua'` prints nothing.
8. Post-merge smoke:
   - B1: `python3 .devtools/bin/ingame_tests.py --maps koth_viaduct,cp_dustbowl`
     exits 0, with 0 Lua errors.
   - B2: the same over the Halloween maps whose `bosses` step covers all
     three boss classes. To list them:
     `cd .devtools/bin && python3 -c "import ingame_tests as t; [print(r.map, [s.args for s in r.steps if s.check == 'bosses']) for r in t.full_plan()]"`
     (it reads the BSPs, read-only). The run exits 0 with 0 Lua errors.

---

## Phase C: removing `Define`, and the events file

**Goal.** Remove what the migration needed, and build what the spec's §5
describes.

- **Removed:** the `Define` and type-constructor shims, and the ratchet.
- **Built:**
  - the generated `resource/sandcastle_events.res`;
  - its generator `.devtools/bin/gen_events_res.lua`;
  - the pre-commit hook `.devtools/bin/hooks/pre-commit`;
  - the staleness test;
  - the `wetsand_events_print` / `wetsand_events_print_cl` commands.

This reads the handoff's "(C) removing `Define`, the generator and
pre-commit hook" with the spec: none of the three exists at 38eb752, and
the spec builds them. The operator confirmed it: build all three
(decision 4).

**One programmer.** The writer may start drafting once C lands.

### C.1 Scope

- **`wetsand/sh_events.lua`:** remove `API.Define`, the constructor names,
  and any v1 leftovers.
- **`tests/events_unmigrated.lua`:** deleted. `tests/events_sites_test.lua`
  loses its exemption parameter. The ratchet test becomes
  `no file is exempt from the site rules`, so the count stays.
- **`.devtools/bin/events_scan.lua`** is extended to capture, for each
  event:
  - its site's comment block, `file:line` and id;
  - each field with its trailing comment;
  - its `Listen` sites.
- **`.devtools/bin/gen_events_res.lua [--check]`:** writes
  `addon/gamemodes/sandcastle/resource/sandcastle_events.res` in §5's format,
  with events sorted by name. `--check` exits 1 if the file differs.
- **`.devtools/bin/hooks/pre-commit`:** when a staged `.lua` file contains
  `Events.Fire(`, `Events.Listen(` or `Events.Accept(`, it runs the
  generator and stages the file. It must not commit or sign, so the gpg
  rules are unaffected.
  - Enabling it is the operator's one-time step:
    `git config core.hooksPath .devtools/bin/hooks`. The programmer doesn't
    change git config.
  - If `.git/hooks` holds an active hook, the report says so, because
    `core.hooksPath` would bypass it.
- **`tests/events_res_test.lua`:** fails when the committed file differs
  from the generator's output (it shares the scanner, without running a
  subprocess).
- **The print commands (pure part).** A formatter in
  `foundation/events.lua`, `Library:Report()`, lists each event:
  - its listeners (id and key);
  - whether it is accepted, and its rate;
  - its fire count;
  - the tags observed per field on the wire;
  - the stale keys.
- **The print commands (adapter part).** The adapter registers
  `wetsand_events_print` (server; admins only, or the console) and
  `wetsand_events_print_cl` (client). Both print, and never write the
  repository.
- **`critical` stays, unused** (decision 3). The option is still
  validated and recorded in `Sites()`, and `Stops.Blocks` keeps its
  critical branches and their tests, but no `Fire` site passes it. Nothing
  is removed for report only: A built no stopping into the adapter.

### C.2 Tests to write first

- `tests/events_res_test.lua`:
  - `the committed events file is what the Fire sites generate`
  - `an edited comment above a Fire site changes the generated file`
    (on a fixture)
- `tests/events_scan_test.lua` adds:
  - `a site's comment block and its fields' trailing comments are captured`
  - `the generated entry lists fired file:line, the id in hex, and each heard file`
- `tests/events_test.lua` adds:
  - `the report lists listeners, accepts, fire counts, observed tags and stale files`

### C.3 Acceptance criteria

1. The per-commit checks pass on every commit.
2. `grep -rnE '\bDefine\b|\bUInt\b|\bOptional\b|\bRecord\b' addon/gamemodes/sandcastle/gamemode/wetsand/sh_events.lua`
   prints nothing, and `grep -rn '\.Define(' addon --include='*.lua'`
   prints nothing.
3. `test ! -e tests/events_unmigrated.lua && ! grep -rn 'unmigrated' tests .devtools/bin`
   succeeds.
4. `luajit .devtools/bin/gen_events_res.lua --check` exits 0, and the file
   starts with
   `// GENERATED by .devtools/bin/gen_events_res.lua from each Events.Fire; do not edit.`
5. The number of events in the file equals the number of distinct `Fire`
   names the scan reports (both printed by `gen_events_res.lua --count`).
6. The staleness test bites. In a scratch export (`git archive HEAD | tar -x -C <scratch>`):
   1. append a line to the `.res`;
   2. `luajit tests/events_res_test.lua` exits nonzero;
   3. restore the file, and it exits 0.
7. The hook works. In a scratch clone with `core.hooksPath` set:
   1. edit the comment above one `Fire` site;
   2. `git add` the file;
   3. commit with `git -c gpg.program=gpg-loopback commit -m test`;
   4. `git show --stat HEAD` lists the `.res`.
8. `.devtools/bin/check_engine_names.sh wetsand_events_print wetsand_events_print_cl`
   prints `free` for both.
9. Post-merge smoke: `ingame_tests.py --maps koth_viaduct` exits 0. Then
   `srcds.py start --map koth_viaduct` and
   `srcds.py rcon wetsand_events_print` prints `client_ready`,
   `events_accepted`, `feature_load` and `teamplay_point_captured` with
   their sites.
10. `critical` is built but unused (decision 3):
    `grep -rnE 'critical *= *true' addon --include='*.lua'` prints nothing
    (0 at 29a6070), and `luajit tests/events_stops_test.lua` still passes
    its critical tests.

---

## Phase D: presentation moved to client listeners

**Goal.** Where the server picks an announcer line or builds gameplay text
from state that a fact event can carry, fire the fact on its TF2-named event
and let the client listener pick and play.

- **Lines that stay on `teamplay_broadcast_audio`:** those named by map
  data, or chosen by a model's own pick. TF2 broadcasts those from the
  server too.
- **Text that stays:** admin-command replies.

**One programmer, plus the writer drafting** (that's two agents).

### D.1 Scope: the 19 `BroadcastSound` calls

| Site | Line or rule | Decision | Event the client listens to |
|---|---|---|---|
| `features/rounds/sv.lua:193,196,197` (`PlayWinSong`) | stalemate; each side's win or loss | **Move** | `teamplay_round_win` (TF2's: `team`, `winreason`, `full_round`, ...) |
| `features/rounds/sv.lua:762` (`RoundWinLines`) | the mode's win lines | **Move** | `teamplay_round_win`, plus the fields `RoundWinLines` reads (for example `multiple_trains`) |
| `features/rounds/sv.lua:203,204,206` (`AnnounceTimeAdded`) | the credited team's lines | **Move** | `teamplay_timer_time_added` (exists) |
| `features/rounds/sv.lua:767` | sudden death | **Move** | `teamplay_suddendeath_begin` |
| `features/rounds/sv.lua:665` (`CapSounds`) | `PlaySpecialCapSounds` | **Move** | `teamplay_point_captured`, plus the fields the mode's `CapSounds` reads |
| `features/rounds/sv.lua:330` | the overtime nag | Stay | (TF2 broadcasts it) |
| `features/rounds/sv.lua:927` (`VoiceTo`) | the map's `PlayVO*` inputs | Stay | (the map names the sound) |
| `features/capture/sv.lua:330` | the capture model's "others" line | Stay | (already a client-side hearing rule) |
| `features/holiday/sv.lua:169` | the fortune's broadcast | Stay | (the model's pick) |
| `features/gamemode/sv.lua:57` | the admin's transition line | Stay | (an admin command; its cancel needs the server's record) |
| `features/wheel/sv.lua:106,114` | the Wheel's lines | Stay | (the model's pick) |
| `entities/entities/merasmus.lua:140,147` | Merasmus's lines | Stay | (the model's pick) |
| `entities/entities/team_train_watcher.lua:342` | the cart warning | Stay | (TF2 broadcasts it; no TF2 event) |

**Gameplay text (6 of 23 `ChatPrint`/`PrintMessage` sites).**

| Site | Decision | Event |
|---|---|---|
| `wetsand/sv_teams.lua:137` | Move | `teamplay_alert` (TF2's `alert_type`) |
| `wetsand/sv_teams.lua:155` | Move | `teamplay_teambalanced_player` (TF2's `player`, `team`) |
| `wetsand/sv_teams.lua:108` | Move | TF2's event if `modevents.res` has one, else Sandcastle's own, `to = ply` |
| `features/tag/sv.lua:29,30,31` | Move | TF2's tag events where `modevents.res` has them, else Sandcastle's own. The notice text is built on the client from shared `foundation` constants. |

The other 17 text sites stay: admin replies, console reports, the editor
tool, and `npc/cl.lua:84`, which is already client-side.

**Announcements and gameplay chat (operator decision 5).** Today the
server builds this text and fires it as text:

- `announcement { text, team }`, through `WETSAND.Announce`
  (`wetsand/sv_world.lua:117`);
- `gameplay_chat { title, lines }`, from one site
  (`features/gamemode/sv.lua:72`).

Both events are retired. The server fires facts on Sandcastle's own events
(TF2 has none for these), and client listeners build the same text. The
lines are at 29a6070.

| Site | Text today | After |
|---|---|---|
| `features/gamemode/sv.lua:109` (`OpenTransition`) | `gameplay_chat`: `Gameplay.Describe(MapInfo())`, plus "Gameplay mode begins in N seconds; then choose a team." | `gameplay_transition_started { map, trains, race, points, rounds, flags, seconds }`. The listener in `wetsand/sh_gameplay.lua`'s client block calls `Gameplay.Describe` and adds the line. |
| `features/gamemode/sv.lua:133` (`NOTICE_REQUEST_CHAT`) and `:134` (`NOTICE_REQUEST_ANNOUNCEMENT`) | the AI war's `Story()` (`features/aiwar/sv.lua:2001`): a chat title and lines, or an announcement | `story` becomes facts (`{ size }`; the factions follow from the teams), and one site fires `gameplay_requested { source, notice, story }`. A pure function in `foundation/` (for example a new `foundation/aiwar/story.lua`) builds the text. It is called by the chat listener (`wetsand/sh_gameplay.lua`) and by the announcement listener (`features/rounds/cl.lua`, beside `View:Announce`). |
| `features/gamemode/sv.lua:136` (`NOTICE_CALLED_OFF`) | `gameplay_chat`: "Game called off. Carry on." | The existing `gameplay_transition_cancelled` listener adds the line. |
| `features/gamemode/sv.lua:141` (`NOTICE_SANDBOX`) | `WETSAND.Announce("Gameplay mode has ended. Sandbox mode until a new game begins.")` | `gameplay_sandbox_entered {}`, announced by its listener in `features/rounds/cl.lua` |
| `wetsand/sv_world.lua:117` (`WETSAND.Announce`), and `announcement` in `wetsand/sh_announcer.lua` and `features/rounds/cl.lua` | | Removed. The client's `View:Announce` stays, and `features/capture/cl.lua:266` keeps calling it. |

- The admin replies (`Tell`, `NOTICE_REFUSED` and `NOTICE_DENIED`) stay
  server-side text, like every other admin reply.
- The sounds beside these notices (`PlayToAll`) are the admin's transition
  lines, which stay (the `features/gamemode/sv.lua:57` row above).
- B1 documents the `gameplay_chat` and `announcement` sites first, and D
  then retires them.

**How a move is done:**

- The rule that picks the line moves into (or already is) a pure
  `foundation/` function, which both the old server path and the new
  client listener can be tested against.
- The listener lives in the feature's `cl.lua` (`features/rounds/cl.lua`,
  `features/capture/cl.lua`), in `wetsand/cl_teams.lua` for team text, or
  in `wetsand/sh_gameplay.lua`'s client block for gameplay chat.
- New events get their one literal site with comments, and pass the site
  rules.
- After a move, the server sends no `teamplay_broadcast_audio` for that
  line.

### D.2 Tests to write first

- **The equivalence table.** For each moved rule, a test that the client's
  pick for every (local team, event fields) equals what the server's
  `BroadcastSound(team, line)` plus `foundation.teams.HearsBroadcast` would
  have delivered. Examples:
  - `each side hears its own result, and a stalemate everyone's`
  - `the credited team and its enemy hear their time-added lines`
  - `sudden death is everyone's line`
  - `special cap sounds follow the mode, whether the cap would win, and the score per round`
  - `a round's win lines follow the mode, the round and the number of trains`
- **The notices.** Tests for the tag notices' client text, and for the
  team-full and balance text: `each tag notice reads as the server printed it`.
- **The gameplay notices** (decision 5), in a new
  `tests/gameplay_notices_test.lua`, with at least these four tests:
  - `the transition chat reads as the server built it`, over a corpus of
    map infos: payload, race, koth, cp with stages, ctf, arena and none;
  - `the AI war's chat and announcement read as its story built them`,
    for several team sizes, against the old `Story()` strings;
  - `the called-off line reads as the server built it`;
  - `the sandbox announcement reads as the server built it`.

### D.3 Acceptance criteria

1. The per-commit checks pass on every commit.
2. `grep -rnE 'WETSAND\.BroadcastSound(ToOthers)?\(' addon --include='*.lua' | grep -v 'function WETSAND' | wc -l`
   prints 10, and these are exactly the Stay rows above:
   `grep -nE 'WETSAND\.BroadcastSound' addon/gamemodes/sandcastle/gamemode/features/rounds/sv.lua`
   shows only the nag and `VoiceTo` lines.
3. `grep -nE 'PrintMessage\(|ChatPrint\(' addon/gamemodes/sandcastle/gamemode/wetsand/sv_teams.lua addon/gamemodes/sandcastle/gamemode/features/tag/sv.lua`
   prints nothing. The repo-wide count of `:ChatPrint(` plus `PrintMessage(`
   is 17.
4. `luajit tests/events_sites_test.lua` passes. The new events appear in the
   regenerated `.res`, and `gen_events_res.lua --check` exits 0.
5. Post-merge:
   `python3 .devtools/bin/ingame_tests.py --maps koth_viaduct,cp_dustbowl,pl_millstone_event`
   exits 0 with 0 Lua errors.
   - The `koth` and `cp_capture` checks gain a server-side listener record
     showing `teamplay_round_win` fired with a `team` field when the round
     ended.
   - `test_ingame_tests.py` is updated if the plan's steps change, and
     pytest passes.
6. The harness's `HUMAN_ONLY` list still names the announcer lines. Hearing
   them is a playtest item for the operator, not an agent criterion.
7. `WETSAND.Announce`, `announcement` and `gameplay_chat` are gone:
   - `grep -rnE 'WETSAND\.Announce\b' addon --include='*.lua'` prints
     nothing. At 29a6070 it prints 3 lines: the definition and its 2
     callers.
   - `grep -rnE '"(announcement|gameplay_chat)"' addon --include='*.lua'`
     prints nothing. It prints 6 lines at 29a6070, and B1 leaves 4.
8. No server file builds the moved text:
   `grep -rlE 'AI war declared|Game called off|Gameplay mode has ended|Gameplay mode begins in|Gameplay\.Describe\(' addon --include='*.lua' | grep -E '/sv(_[^/]*)?\.lua$'`
   prints nothing. At 29a6070 it prints `features/gamemode/sv.lua` and
   `features/aiwar/sv.lua`.
9. `luajit tests/gameplay_notices_test.lua` passes, and contains the four
   test names in D.2.

---

## Phase E: in game

**Goal.** Run the whole system live:

- the harness on the 14 maps with zero Lua errors;
- a staged stale-file check on one map, without a client and with one;
- T1 to T5 with the GMod client in "Team Fortress 2" (operator decision 2),
  unattended, through `gmod_client.py` (§3).

**One programmer** (it runs the harness and the client session), plus the
writer finishing the docs.

### E.1 Scope

- **A new in-game check,**
  `.devtools/bin/ingame/checks/events_stale.lua`, added to koth_viaduct's
  `MapRun` in `ingame_tests.py`, with `test_ingame_tests.py` updated. It
  stages staleness **without editing any addon file**:
  1. It replaces the drift record's sent and run references for
     `gamemode/features/capture/cl.lua` with a different hash.
  2. It waits one full scan cycle.
  3. It asserts the scanner reports the key as stale.
  4. It calls the server's `client_ready` trigger path for a fake sender
     key, and asserts a `code_stale` is produced naming that key.
  5. It feeds a fake `code_touched { events = { "teamplay_point_captured", "teamplay_capture_blocked" } }`
     from that sender.
  6. It asserts two things. `Stops.Blocks`, called directly with the live
     library's `Sites()`, holds for those two events and not for
     `teamplay_timer_time_added`: attribution feeds the model correctly.
     And the adapter would still send that sender all three: nothing stops
     (decision 3).
  7. It asserts the server log has one `network error:` line naming the
     key.
  8. It restores the references.
- **The client's staged stale file** (with the client, and §3's markers):
  1. Start the server on koth_viaduct and wait for start-up.
  2. Set a comment marker in `features/capture/cl.lua` and
     `lua_refresh_file` it. It is a `CompileFile`d file, so the server
     keeps running the old text while later joiners get the new one (T2).
  3. Wait one scan cycle, then launch the client.
  4. The client's log has the `network error:` line for
     `gamemode/features/capture/cl.lua`, naming `teamplay_point_captured`
     and `teamplay_capture_blocked` as touched and not stopped. The
     server's log has its one line for that player.
  5. Close the client, restore the marker, and stop the server.

  If T2 chose `SERVED_SENT`, a refreshed feature file is never stale. The
  architect then replaces steps 2 and 3 with a lazily compiled server
  module's case before E starts.
- **`SERVED_TEXT`** was set in A from T2. If E's run of T2 disagrees, the
  programmer reports it, and the architect decides before E passes.
- **The client session** (§3): T1 to T5 on the finished main, with the
  staged stale file above, in one session. The programmer appends the
  results to the research file under `## Client session (E)`.

### E.2 Tests to write first

- `test_ingame_tests.py`: koth_viaduct's plan includes `events_stale`.
- The `events_stale.lua` check fails on main before the drift record is
  reachable, which shows it reads the live library.

### E.3 Acceptance criteria

1. The harness:
   `python3 .devtools/bin/ingame_tests.py --maps pl_fifthcurve_event,pl_rumble_event,pl_millstone_event,pl_bloodwater,pl_terror_event,pl_hasslecastle,pl_sludgepit_event,plr_hacksaw_event,plr_hightower_event,pl_precipice_event_final,pl_coal_event,koth_viaduct,cp_granary,cp_dustbowl`
   exits 0.
   - Every row of the report's summary is PASS, with Lua errors 0.
   - The report's path is given in the programmer's report.
2. The `events_stale` step on koth_viaduct is PASS in that same run.
3. The per-commit checks pass, and `cd .devtools/bin && python3 -m pytest -q`
   passes.
4. **The client session** (operator decision 2; §3), unattended, on main
   after D merges. All of these are required:
   - T1 to T5 are recorded in the research file under
     `## Client session (E)`, each with its output under
     `.devtools/artifacts/gev2-research/client/`.
   - T1 passes, or A.4 was re-planned when it failed in A.
   - T3's `client_t3.txt` ends `mismatches 0` for both directions.
   - `UNRELIABLE_MAX_BYTES` is set from T5: at most half the largest size
     that arrived 100 out of 100 under load, and below 4000.
   - `tests/events_paths_test.lua` has T4's client form as a case, if it
     differs from the three.
   - The client's staged stale file (E.1) passes: the client's log has the
     `network error:` line for `gamemode/features/capture/cl.lua`, and the
     server's log has one line for that player.
   - Every client log has 0 Lua errors. For each
     `.devtools/artifacts/gev2-research/client/client_console-*.log`,
     `cd .devtools/bin && python3 -c "import ingame_tests as t, pathlib, sys; print(len(t.lua_errors(pathlib.Path(sys.argv[1]).read_text())))" <log>`
     prints 0.
   - The safeguards held. `gmod_client.log` shows every launch's
     preflight, one PID launched per launch, and that PID (and only it)
     closed. Afterwards `ps -axo command= | grep -c '[g]mod_win64.exe'`
     prints 0, and `git status --short` is what it was before the
     session.

---

## 3. The client tests (T1 to T5)

**Operator decision 2: allowed, unattended.** The GMod client runs in the
CrossOver bottle **"Team Fortress 2"**, which has the right Wine settings.
It joins the dedicated server that `srcds.py` runs in "Steam".

- It is the only thing that ever runs in "Team Fortress 2" for this work,
  and only `gmod_client.py` launches or closes it.
- The operator plays TF2 in that bottle, and a server there once ended his
  game. So the tool's safeguards are its tested behaviour (A.5).

**The shared install.** The "Steam" bottle's
`C:\Steam\steamapps\common\GarrysMod` is a symlink into the "Team Fortress
2" bottle's, so the client and the server read one `garrysmod/` folder:

- **`addons/sandcastle`,** the symlink to this repo, is both the server's
  copy and the client's local copy. The two can only differ in time, which
  is how T1 is staged.
- **`data/`:** the client reads its probes from `data/wetsand_tests/` and
  writes its results there, as the server does.
- **`cache/lua/`:** the dedicated server writes nothing there (research
  §1), so every entry is the client's.
- **`console.log`** is the server's `-condebug` log. The client never uses
  `-condebug`. It logs with
  `+con_logfile data/wetsand_tests/client/console.log` instead.

**`gmod_client.py`** (A.1; its tests are in A.5):

```sh
gmod_client.py check                                  # the preflight alone: exit 0 if a launch is allowed, 3 if not, saying why
gmod_client.py start [--port 27025] [--minutes 20]    # preflight, launch, wait until the server's status lists the player
gmod_client.py stop                                   # close the client this tool launched, and keep its log
```

- **The preflight, before every launch.** It refuses, and launches
  nothing, when any of these holds:
  - any `tf_win64.exe`, `tf.exe` or `hl2.exe` runs, in any bottle (the
    operator's TF2). Refusing on the name alone is stricter than working
    out which bottle a process is in.
  - any `gmod.exe` or `gmod_win64.exe` runs: the operator's GMod, or a
    client a previous run left.
  - no `steam.exe` runs in "Team Fortress 2". A process is in that bottle
    when its working directory, from `lsof`, is under the bottle's folder.
    Launching GMod without Steam would start Steam, a second program in
    the operator's bottle, so the tool leaves that to him and refuses.
  - its own PID file names a client that still runs.
- **The launch is one command:** the bottle's `wine` with
  `--bottle "Team Fortress 2"`, running
  `gmod_win64.exe -novid -nojoy +con_logfile data/wetsand_tests/client/console.log +connect 127.0.0.1:<port>`.
  - The bottle is a constant, and the tool has no option for another one.
    `srcds.py` still refuses this bottle.
  - The tool records the client's PID and its start time in
    `.devtools/artifacts/gmod_client.pid`. The client is the one
    `gmod_win64.exe` process that wasn't running before the launch, found
    the way `srcds.py`'s `new_server` finds its server.
  - It appends what it found and did to
    `.devtools/artifacts/gev2-research/client/gmod_client.log`.
- **The watchdog** is a detached supervisor, like `srcds.py`'s, that checks
  every 2 s. It closes the client when the operator's game starts (any of
  the names above, other than our PID), or when `--minutes` pass. So a
  crashed agent never leaves the client running.
- **Closing.** `stop` and the watchdog signal only the recorded PID:
  - `SIGTERM`, then `SIGKILL` 15 s later if it still runs;
  - only while that PID still runs `gmod_win64.exe` with the recorded start
    time, so a reused PID is left alone;
  - never the wine launcher, a wineserver, wine's services (`srcds.py`'s
    `NEVER_STOP`), `steam.exe`, `steamwebhelper.exe`, or anything found by
    name or pattern.

  Then `stop` copies the client's log to
  `.devtools/artifacts/gev2-research/client/client_console-<UTC time>.log`.
  `gmod_client.log` lists any `garrysmod/cfg/*.cfg` whose content changed
  during the run, so the operator can see whether GMod saved settings.

**Markers.** T1, T2 and E's client check need an uncommitted change to an
addon file that the server reads through main.

- `gev2_marker.py set <file> <line>` appends the line. It refuses a file
  with uncommitted changes, because the operator may be working on main.
- `gev2_marker.py restore` puts back the exact bytes it saved. Every run
  calls it in a `finally`.
- Markers are never committed, and `git status --short` must be unchanged
  afterwards.

**Running a probe on the client.** `gev2_probe.py run --client NAME`:

1. copies `.devtools/bin/gev2/NAME.lua` to `data/wetsand_tests/gev2/`;
2. over RCON, has the server `SendLua` each connected player a one-line
   loader, which `RunString`s the probe from the client's `data/` (the
   shared folder). This works with `sv_allowcslua 0`, which every test
   keeps;
3. waits for the client to write `data/wetsand_tests/gev2/client_out/NAME.txt`,
   and copies it to `.devtools/artifacts/gev2-research/client/`.

| Test | When | What it settles | What each result changes |
|---|---|---|---|
| **T1** | early A; again in E | With `sv_allowcslua 0`, does the client run the copy the server sent rather than its local copy, for `include` and for `CompileFile` (`WETSAND.require`, the feature loader)? And after joining, do the client's `cache/lua` names match the server's `util.SHA256(text .. "\0"):sub(1, 40)` list for every sent file? **Staging** (the install is shared, so the copies can differ only in time): (1) set the marker `WETSAND_T1_INCLUDE = "sent-<nonce>"` in `wetsand/cl_spectate.lua` (`include`d) and `WETSAND_T1_COMPILE = "sent-<nonce>"` in `features/capture/cl.lua` (`CompileFile`d); (2) start the server with `--no-lua-refresh` on koth_viaduct, which loads `capture`; (3) rewrite both markers to `"disk-<nonce>"`; (4) launch the client; (5) the probe reports both globals, and the cache check runs. | **Pass:** both read `sent-`, and the cache holds the `sent-` texts. The engine guarantee holds, and the server-side check is complete. **`disk-`, with the cache holding the `disk-` text:** the server serves disk text even without a refresh. The guarantee still holds, and T2 should choose `SERVED_DISK`. **`disk-` with no matching cache entry, or a mix:** the premise of §4 is false. The architect re-plans A.4 with the operator before detection is built (A.6 item 11). The codec, rates and stop rules are unaffected. |
| **T2** | early A; again in E | After `lua_refresh_file` of `features/capture/cl.lua`, and after a plain save (in case autorefresh fires under CrossOver), each with a new marker: does the connected client gain the new cache entry, and does a client that joins next (a second launch) run the new text? | **New text for later joiners after a refresh, and after a plain save:** `SERVED_DISK` is exact. **After a refresh only:** keep `SERVED_DISK`, and the report says "differs on disk; stale for clients that load it after a refresh". **Never before a map change:** set `SERVED_SENT`, and drift can then come only from lazily compiled server modules. |
| **T3** | after A merges; again in E | The wire through real `net`, in both directions, with A's codec: every tag of A.3, `""`, a NUL string, the caps, `WriteUInt` at 32 bits with values ≥ 2^31, and `ReadData` with NUL bytes | The fake buffer is the only other evidence for the read side. Any mismatch is a codec defect, fixed in A (or, in E, before E passes). |
| **T4** | early A; again in E | `debug.getinfo(fn, "S").source` on the client, for a server-sent file, a feature view and an entity | If it is a fourth form, `Paths.Key` gains it as a test case in A. Attribution on the client depends on it. |
| **T5** | E | The largest unreliable message that reliably arrives: 200, 500, 1000, 1200, 2000 and 4000 bytes, 100 of each, idle and under load | Sets `UNRELIABLE_MAX_BYTES`. No event is unreliable yet, so nothing waits on it. |

**Who runs what, and when.**

- **Early A,** by the researcher (the second agent): T1, T2 and T4.
  - They start as soon as the programmer's client tools are committed on
    the A branch, using that worktree's scripts against main.
  - The results go in the research file under `## Client session`.
  - Detection waits for T1 and T2 (A.6 items 11 and 14).
- **After A merges,** by the A programmer, before the architect's A
  evaluation: T3 (A.6 item 15).
- **E,** by the E programmer: all five again on the finished main, plus the
  client's staged stale file (E.1), in one session (E.3 item 4).
- **Every session runs in this order:**
  1. `srcds.py start`;
  2. `gmod_client.py start`;
  3. the probes;
  4. `gmod_client.py stop`;
  5. `srcds.py stop`.

  The markers are restored in a `finally`.

---

## 4. Operator decisions

All five were answered on 2026-10-08, and none is open. The questions, the
answers and what they changed are under "Operator decisions (2026-10-08)"
near the top. The researcher's two product questions were decisions 1 and
2.

---

## 5. Order of work, the two-agent limit, and risks

### Order

| Step | Agents running (at most 2) | Gate to the next step |
|---|---|---|
| 0. Commit the research inputs and this plan (approved, with §4 answered) | director | the commit is on main |
| A. The library (A.1–A.6) | programmer; plus the researcher for the early client session (T1, T2, T4) | A.4's detection waits for T1 and T2's results; T3 runs after the merge; architect's A evaluation passes |
| B. Migration | programmer B1 and programmer B2, in parallel on disjoint files | both merged; architect's B evaluation passes |
| C. Removal and the events file | programmer | architect's C evaluation passes |
| D. Presentation | programmer D; the writer starts drafting | architect's D evaluation passes |
| E. In game | programmer E (the harness and the client session, T1 to T5); the writer continues | architect's E evaluation passes |
| Docs finish, close | writer, then director | |

- **The two-agent limit applies:**
  - in A, the programmer plus the researcher, who runs only the early
    client session;
  - in B, the two programmers. The writer doesn't start in B, and the
    researcher doesn't run then;
  - in D and E, the programmer plus the writer.
- **Merging and evaluation.** After each phase the director merges with
  `--no-ff` and runs both checks on main. The architect then runs that
  phase's criteria, including the post-merge smoke. A failed criterion goes
  back to the programmer before the next phase.

### Risks

1. **Only a client exercises the real wire.**
   - The dedicated server has no client, so `net` decode is proven live
     only by T3. Until T3 runs, the codec rests on a fake buffer that mimics
     GMod's bit costs (measured in research §4).
   - Mitigations: A's live size probe proves the write side exactly, and T3
     runs as soon as A is merged (A.6 item 15), then again in E.
   - Known suspects T3 checks: `WriteUInt`/`ReadUInt` at 32 bits for values
     ≥ 2^31, and `ReadData` with NULs.
2. **`file.Time` under Wine through a symlink is unmeasured.** If it is
   costly or doesn't change on save, the scanner reads in turn. That costs
   about 0.7 ms per file, so `FILES_PER_TICK` drops to 1 and a full cycle
   takes about 3 s at 66 ticks. The 1 ms per-tick budget is checked in A.6.
3. **Start-up reads every sent file once** (126–163 ms under Wine), for the
   sent references. This happens once per map, never per join.
4. **Wrapping a global.** Another addon may wrap `AddCSLuaFile` too. Ours
   chains to the previous function, and is installed once per Lua state. A
   gamemode refresh reruns `init.lua`, and the kind rules (A.4) decide which
   references refresh.
5. **Detection can over-report** if T2 shows that a plain save (with no
   refresh) doesn't change what later loaders run. The report's wording
   follows T2's result. Detection only reports (decision 3), so an
   over-report costs a console and chat line, never a lost event.
6. **Merges in B.** The shared file is `tests/events_unmigrated.lua`. Its
   two blocks are far apart, so the edits merge cleanly. If they don't, the
   conflict is two lists that both end empty. No other file is in both
   sets.
7. **The boss port change touches three large models and five tests.** The
   per-file test counts (B.3 item 6) guard against lost coverage.
8. **Client sound choice needs client-side state.** The mode, trains and
   score per round must travel as event fields, or already be known to the
   view. A wrong field shows up as a wrong line, which only a human hears.
   The equivalence tests (D.2) are the guard.
9. **The spec lags the plan** until the writer applies §1. Programmers must
   read §1 first. The evaluator judges against this plan.
10. **E's harness run is long** (14 maps, with boss steps of 150 s each). Run
    it once, with nothing else on the server.
11. **The client runs in the operator's bottle.** The preflight, the
    watchdog and PID-only closing (§3) are the guards, and they are tested
    (A.5).
    - What remains: the operator starting TF2 during a run, which the
      watchdog answers within 2 s by closing only our client.
    - GMod may save its own settings when it closes. `gmod_client.log`
      lists any `cfg/*.cfg` that changed.
12. **The shared install.** The client and the server share `garrysmod/`.
    - So the client logs with `con_logfile`, never `-condebug`.
    - Its probes and results stay under `data/wetsand_tests/`.
    - T1 is staged in time, not with a second copy of the addon (§3).

### Judgment calls the operator may want to revisit

- **Hashing compiled text.** The run reference comes from `file.Read` just
  before `CompileFile`, not from `CompileString`. This keeps chunk names and
  error paths; the cost is a microsecond window in which the file could
  change between the read and the compile.
- **The boss port.** It gets one method per event, and the `Fire` sites
  live in `features/npc/sv.lua`, not in the entity. That way the events
  belong to the `npc` feature beside the view that hears them. The
  alternative is literal sites in `halloween_base_boss.lua`, which would
  make the events always loaded.
- **`Listen` is literal too, with a function-literal listener.** Without
  that, the spec's field check can't be built.
- **`tests/events_test.lua` is rewritten in A, and `Request` is removed in
  A.** The v1 registry's tests are replaced in the commit that replaces the
  registry, so the test total never drops.
- **Stopping is modelled, not enforced** (decision 3). `Stops` defines
  which events a stale file would stop, feature-wide and all-event stops
  included, and its tests pin that down. No runtime code stops an event.
  Client-only events are never stopped, even in the model.
- **No `wetsand_events_check` convar.** Report only leaves its off and stop
  values without a use, so the check always runs. `code_stale` has no
  `stop` field, and the client's answer is `code_touched`.
- **The client sessions.** T1, T2 and T4 run early in A, as the gate for
  detection. T3 runs after A merges, and all five run again in E.
- **The client's preflight** refuses by process name, machine-wide. It also
  refuses when Steam isn't already running in "Team Fortress 2", rather
  than start it there.
- **T1 is staged in time** (markers rewritten after the server starts with
  `-disableluarefresh`), because the shared install makes the client's
  local copy the server's own.
- **D's new events are Sandcastle's own** (TF2 has none):
  `gameplay_transition_started`, `gameplay_requested` and
  `gameplay_sandbox_entered`. `gameplay_requested` carries the source's
  facts as a `story` record, so the gamemode stays generic.
- **The site comments are enforced by the scanner** (a comment block above
  each `Fire`, and a trailing comment on each field line). The spec calls
  them the documentation, so a missing one is a failing test.
- **The constants:**
  - `UNRELIABLE_MAX_BYTES = 1200`, provisional until T5 in E;
  - `READY_BURST_MAX_BYTES = 131072`, logged rather than raised;
  - `FILES_PER_TICK = 2` to start;
  - `MAX_DEPTH = 16`;
  - the wire widths in A.3.
- **The phase-D split.** Lines named by map data or by a model's own pick
  stay on `teamplay_broadcast_audio`, as TF2 itself does. The overtime nag
  and the cart warning stay because TF2 has no event for them.
- **The generator is in Lua,** sharing one scanner with the tests, not
  Python as the spec named it.
