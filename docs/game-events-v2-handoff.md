# Handoff: building game events v2

**For a fresh session.** Game events v2 is the last system before the
fine-tune to the alpha playtest (operator's roadmap). The design is agreed
and written: `docs/game-events-v2.md`. This file says where things stand,
which agent does what, the order of work, and the rules every agent keeps.

## 1. Where things stand (2026-10-07, main at ca41321)

- **Done before this:** the in-game test harness, Merasmus with the whole
  Wheel of Fate, the race-map setup fix (all 11 Halloween payload maps
  pass), TF2's strings in the player's language (`WETSAND.Localize`), and
  the NextSoldier debugging tools. The suite is 1357 LuaJIT tests, all
  green, plus 65 Python tests for the harness.
- **Events today** (`docs/game-events.md` describes them):
  - The model is `foundation/events.lua` (515 lines) and the adapter
    `wetsand/sh_events.lua` (152 lines), tested by `tests/events_test.lua`.
  - 29 `E.Define` calls across 9 files, 20 `Fire` sites and 20 `Listen`
    sites.
  - One client request, `client_ready`.
  - Two net messages for the whole gamemode; only the adapter touches `net`.
- **Still server-side presentation**, the spec's last phase: 23
  `WETSAND.BroadcastSound` calls choose announcer lines on the server
  (rounds, capture, payload, holiday, gamemode), and about 20
  `ChatPrint`/`PrintMessage` sites send text. Many of the text sites answer
  admin commands and should stay; the gameplay ones move.
- **Worktrees:** none in use. `worktree-agent-a297be6dbbd80c1fa` is the
  shelved Rust nav spike; leave it.

## 2. The design in one paragraph

Read `docs/game-events-v2.md` in full before planning. In short: no
`E.Define`. `Fire` runs the local listeners and the library carries the
event to the other realm, with self-describing encoding (type-tagged values
and a key table). Each event has exactly one literal `Fire` site: its table
literal is the event's spec, and its comments are the docs. Clients send
only what the server `Accept`s, with a rate limit. A runtime hash check makes
sure each client file matches the server's. A stale file stops only the
events it touches, and an event marked `critical` stops its feature. A
pre-commit hook generates `resource/sandcastle_events.res` as documentation
only, and a test fails if it is stale. Nothing on the wire can go stale;
there is one source of truth.

## 3. The agents and their jobs

The **director** runs this handoff from start to finish. It delegates each
task to the agent whose kind of work it is, never doing that work itself,
and keeps **at most two agents running at once**, both on this system (the
operator's rule: focus, don't spread thin).

| Agent | Job here | Delivers |
|---|---|---|
| **director** | Runs §4 in order, dispatching the others, merging between phases (§5), and resuming any agent a usage limit stops. | The phase-by-phase report to the operator |
| **researcher** | Answers the open questions in §4 step 1 with evidence: GMod's wiki and source, and tests on the dedicated server where a question needs one. | `docs/game-events-v2-research.md` |
| **scholar** | Judges the riskiest claims against the research, giving a verdict on each: §4 of the spec (the client hashing what it really loaded) and §3's encoding against the net limits. It says plainly where the spec must change. | Verdicts appended to the research file |
| **architect** | Turns the spec, research and verdicts into a plan with acceptance criteria for each phase. After each phase, it judges the work against those criteria. | `docs/game-events-v2-plan.md`, then a pass/fail evaluation per phase |
| **programmer** | Builds each phase in its own worktree, tests first, and runs the checks. It also runs the in-game harness for the live phase. | Signed commits on its branch, plus a report |
| **writer** | Writes the docs once the code has landed: `docs/game-events.md` replaced by the v2 reference, every doc that names `E.Define` updated, and a closing journal entry for the operator. | Docs |

## 4. Order of work

Each step finishes before the next starts, unless it says otherwise.

1. **Research** (researcher). Open questions:
   1. Can client Lua hash the copy of a file it actually ran? Check that
      `file.Read(path, "LUA")` on a client returns the server-sent copy.
      Does a Workshop copy of the addon shadow it, and in which order?
   2. How can the server list the files it sends clients? GMod has no API
      for this, so check whether wrapping `AddCSLuaFile` or reusing
      init.lua's directory walk is reliable, lazy-loaded features
      included.
   3. Lua autorefresh: when the server reloads a file, in what order does
      the client receive it, and does `OnReloaded` fire on both realms?
   4. The net limits: message size (about 64 KB), what `WriteDouble`
      costs, and the size limit for unreliable sends.
   5. `debug.getinfo` source paths in GMod, for working out which feature
      a `Fire` or `Listen` site belongs to (the `addons/...` and
      `gamemodes/...` path forms).
   6. The cost of hashing about 360 files at client join, comparing
      `util.CRC` with `util.SHA256`.
2. **Judgment** (scholar), on the research. The architect starts only
   after this.
3. **Plan** (architect). Its phases follow the spec's §6 migration, plus a
   live phase:
   - (A) the library behind today's API;
   - (B) migrating each feature;
   - (C) removing `Define`, the generator and pre-commit hook, and the
     staleness test;
   - (D) presentation moved to client listeners;
   - (E) in game: the harness on the 11 Halloween payload maps plus
     koth_viaduct, cp_granary and cp_dustbowl, with zero Lua errors,
     plus a staged stale-file check on one map.

   **The operator approves the plan before phase A starts.**
4. **Phases A to E** (programmer, then the architect evaluates). One phase
   at a time: the programmer builds and reports, the director merges
   (§5), and the architect judges. A failed criterion goes back to the
   programmer before the next phase. B may run as two programmers on
   disjoint features (the two-agent limit), never more.
5. **Docs** (writer), after E passes. It may start drafting once C
   lands, while D and E run: that's the second agent.
6. **Close** (director): the final report, and the roadmap moves on to the
   fine-tune.

## 5. Rules every agent keeps

These come from the operator's standing instructions; most are in
`~/.claude/CLAUDE.md` and the project memory.

- **Code style:** load the `lua` skill.
  - Models in `foundation/` are pure `module(...)` files, with LuaJIT
    tests written first and seen failing.
  - Controllers coordinate; entities are thin bindings; clients present.
  - Named constants; one field per line in multi-field tables.
  - No `TF2`/`tf2` in our own identifiers (`check_names.py` enforces it).
  - Never give an ENT function a name the engine's metatable already has.
  - Load lazily per map: no always-loaded file for one mode's content.
- **Names:**
  - NextSoldier's commands and convars are `ns_<subject>_<verb or
    specifier>`.
  - Meta and debug utilities use `wetsand_`, again with a verb
    (`wetsand_events_print`).
  - Gameplay settings use Source's `mp_`, `sv_` and `cl_`; TF2's own names
    are kept where TF2 defines them.
  - Internal ids (hooks, net messages, networked keys) keep `wetsand_`.
  - Check every new console name with `.devtools/bin/check_engine_names.sh`.
  - Every new convar goes into `addon/cfg/sandcastle_defaults.cfg` at its
    default (`tests/cfg_defaults_test.lua` enforces it).
- **Commits:** small, signed with
  `git -c gpg.program=gpg-loopback commit -m "..."`. No Co-Authored-By, no
  Claude attribution, no push. `.devtools/bin/check_lua.sh` and
  `python3 .devtools/bin/check_names.py` pass before each commit, and the
  test total never drops.
- **Merging (director):**
  1. Check every commit is signed (`%G?` is `G`) and carries no
     attribution lines, and that the worktree is clean.
  2. Merge with `git merge --no-ff`.
  3. Run both checks on main.
  4. Keep a worktree until its agent is truly done: a removed worktree
     can't be resumed.
- **The game:** run test servers only through `.devtools/bin/srcds.py`,
  which works in the CrossOver bottle **"Steam"** only. Never launch or
  kill anything in the bottle **"Team Fortress 2"**: the operator plays
  there, and a server in it once ended his game.
  - Never touch `garrysmod/addons/` or the `sandcastle` symlink. The server
    loads main through that symlink, so merge before testing live.
  - Write only under `garrysmod/data/wetsand_tests/`. Stop your server
    when done.
  - TF2 is mounted through `cfg/mount.cfg`. DrGBase doesn't load on the
    dedicated server, so the AI war can't be checked there.
- **Layout:** reusable scripts go in `.devtools/bin/`, reports in
  `.devtools/artifacts/`, docs in `docs/`. The scratchpad holds data only.
- **Escalate only product questions** to the operator. Technical calls
  belong to the architect, then the programmer.

## 6. Starting the fresh session

Paste this to start:

> Read docs/game-events-v2-handoff.md and run it with the director agent:
> research and judgment first, then the architect's plan, which I approve
> before any code.
