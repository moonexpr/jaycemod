# NextSoldier performance baseline (2026-10-16)

What a 15v15 AI war costs the server today, and what causes the cost,
before NextSoldier and the tactics engine take on more behaviour. This
identifies causes only; solutions are for a later discussion.

## Setup

- Dedicated server (CrossOver bottle GModServer, port 27025), pl_upward,
  66 ticks/s (15 ms tick budget), no players.
- AI war at `mp_aiwar_team_size 15`: 30 soldiers (15 Combine; 13 rebels and
  2 vortigaunt medics).
- Mid-game state: BLU owns cap_1 (minecart_path_44's OnPass outputs fired);
  the cart teleported to minecart_path_74, 272 u short of cap_2, the middle
  point. 18 of 30 soldiers fought within 1500 u of the cart.
- Tools: `.devtools/bin/profile_server.lua` (wraps hooks, entity methods,
  feature controller methods, module functions and NS actions; self and
  inclusive time per coroutine, worst single call), plus one-off probes run
  through `server_lua.py`, each named below. Wrapper overhead was measured at
  0.4 µs per call; `SysTime` costs 0.16 µs under Wine.

## Where the time goes (default settings)

| Cost | Size | Shape |
|---|---|---|
| Lua route search (`Think/ws_npc_spawners`, `ThinkSearches`) | 0.2 to 4.3 ms per tick | follows demand; saturated, it spends its 2 ms budget and overshoots to 3 to 4 ms |
| AI war think (`Think/ws_aiwar`): soldiers' behaviour trees and the controller | 1.4 to 1.9 ms per tick | steady; the trees are about 60 % of it |
| Cart riders (`aiwar:CarrySeated`, in `Tick/ws_aiwar_move`) | 0.4 ms per tick | steady, twice a tick |
| Respawn (`Reinforce` → `Draft` → `Enlist` → `RelateToFactions`) | 80 to 200 ms in one tick | hitch at every respawn wave |

Process CPU (`stats`, Wine overhead included): about 65 % with the full war.

## Hypotheses and tests

Each was stated before its experiment, with the result that would refute it.

| # | Hypothesis | Experiment | Result | Verdict |
|---|---|---|---|---|
| H1 | The search queue is full because requests are many, not because searches are big | A: every request's fate and size for 60 s | 25 requests in a quiet window (0.2 ms/tick); the queue never emptied in busy windows | Supported: demand comes in bursts |
| H2 | Most expansions belong to failed searches that hit the cap | A | 2 of 3198 expansions failed; none hit the cap | Refuted |
| H3 | Engine calls in `FillStep` make an expansion expensive | B: 12 captured real requests replayed with each part timed; engine calls benchmarked | Engine calls 0.05 to 0.3 µs each; warm replay 19 to 46 µs per expansion against about 100 to 200 µs live | Refuted as the main cause |
| H6 | Cold caches (neighbours, centres, spawn rooms) slow live searches | D: replay with each cache cleared | Neighbours and centres: no change; spawn rooms: ×2, but it clears only at round changes | Refuted for steady play |
| H7a/b | GC or the JIT explains the replay's run-to-run spread | E: interleaved rounds, blocked by JIT on and off | GC on 20 µs, off 12 µs per expansion; JIT on and off alike when warmed | GC is a minor share; JIT not decisive in replay |
| H9 | Under live conditions the GC makes searches slow | F: live, GC on and off in 15 s blocks (ABAB), injected load | 99.5 / 101.2 / 101.6 / 96.3 µs per expansion | Refuted |
| H10 | The big hitches are GC atomic phases | F: long ticks against memory drops | 6 of 9 long ticks came with GC stopped; 2 of 9 with a drop | Refuted |
| H11 | Round-robin 16-expansion steps are slow in themselves | Replay round-robin against whole searches | 15 to 18 µs either way | Refuted |
| H12 | Live, the JIT makes the Lua slower | G: whole-server JIT on and off, 15 s ABAB blocks | On 97.2 / 116.5 µs per expansion, off 21.5 / 23.2; tick p95 36 / 35 ms on, 18 / 18 off; CPU 79 / 92 % on, 55 / 48 % off | Supported |
| H12a | The JIT thrashes because it runs out of capacity (traces, machine code) | I: defaults, then capacity ×8 (`maxtrace`, `maxmcode`, `maxrecord`, `maxside`, `maxsnap`, `sizemcode`), then less eager, then defaults again | 68.2 → 24.3 → 34.4 → 86.9 µs per expansion; it reverses when the defaults return | Supported |
| H12b | The JIT thrashes on aborted recordings, not capacity | I (less eager: `hotloop` 300, `hotexit` 60) | Helps (34.4) but less than capacity (24.3) | Weaker; fits capacity pressure |
| — | The capacity effect holds for the natural war, not only injected load | J: natural war, defaults against capacity ×8, 20 s ABAB | War think 123.4 / 114.8 ms/s on the defaults, 58.4 / 77.0 with capacity | Supported: the war's main cost halves |
| H5 | The `ws_aiwar` hitch is one periodic controller task | K: controller methods timed with worst call | Worst calls: `Think` 219 ms ⊃ `Reinforce` 197 ⊃ `Draft` 127 (mean 83) ⊃ `Enlist` 95 (mean 57) ⊃ `RelateToFactions` 50 (mean 28); 23 respawns a minute | Supported: respawning is the hitch |

GMod disables LuaJIT's introspection (`jit.attach`: "vmevent API disabled";
`jit.util.traceinfo` returns nil), so H12a rests on intervention, not on a
trace count. The values restored after experiments I and J are LuaJIT
2.1's stock defaults; GMod's own are not readable, and a map change resets
the VM in any case.

## Control: what NextSoldier itself costs

Your proposed control (map loaded, no units) also removes 30 NextBots'
engine work (locomotion, animation, physics, sensing) and DrGBase's AI, so
it can't separate NextSoldier from having units at all. Experiment L holds
the 30 bodies and the scenario fixed and removes only NextSoldier's
decisions: every soldier's behaviour tree stops updating and its steering
targets are cleared, so DrGBase's own AI drives the same bodies. Respawns,
cart riding and the rest of the controller keep running. 20 s blocks,
alternating:

| Block | War think | Movement | Search | Tick p95 | CPU |
|---|---|---|---|---|---|
| full | 60.1 ms/s | 5.7 | 221.6 | 29.9 ms | 64 / 66 % |
| NS ablated | 10.0 | 38.8 | 83.8 | 18.3 | 46 / 43 % |
| full | 67.0 | 8.0 | 224.6 | 29.1 | 65 / 65 % |
| NS ablated | 8.4 | 21.3 | 197.1 | 18.8 | 56 / 47 % |

So NextSoldier's decisions are about 15 to 20 points of the server's
roughly 65 % CPU, and they take the slow-tick p95 from about 18 ms to about
29 ms. Search demand is that of whole queued searches; it fell in the first
ablated block and stayed high in the second while the backlog from the full
block drained. Movement rose when ablated: DrGBase's own chasing moves the
bodies more.

Not yet run from the control design: the think-rate dose (×1, ×½, ×¼ at a
fixed unit count) and the unit-count dose (6, 10, 15 per team). They would
give the cost per soldier and whether it grows faster than linearly, which
matters before adding behaviour.

## Conclusions (identification only)

1. **The JIT's capacity is the largest single factor.** With LuaJIT's
   default limits the server's Lua runs several times slower than it can:
   the route search 3 to 5 times, the war's think about 2 times. Raising
   capacity, or even turning the JIT off, beats the defaults. Every Lua
   system pays this, so new NS behaviour will make it worse.
2. **Route search is the largest demand-driven cost.** Saturated, it spends
   3 to 4 ms of each 15 ms tick: its 2 ms deadline is checked only between
   16-expansion steps, and one step costs 1.5 to 3.3 ms live (worst 17.7 ms).
3. **NextSoldier's decisions are about a quarter to a third of the server's
   CPU** at 15v15 (control L), mostly in the behaviour trees (`Travel`,
   `StrategyMonitor`, `TacticalMonitor`) and the search they ask for.
4. **Respawning causes the hitches**: 80 to 200 ms in one tick per respawn
   wave, in spawning the DrGBase entity, enlisting it, and setting its
   DrGBase faction relationships.

Smaller items: `CarrySeated` at 26.5 ms/s; `Soldier:Blocker` at 9.6 ms/s over
17.5k calls. `query ShouldHurry` shows 23 to 42 µs per call in play against
1 to 2 µs in a benchmark; that gap is unexplained but small (about 1 % of a
core). A vortigaunt's `OnDeath` (287 to 430 ms) is not a cost: it pauses its
coroutine for the ragdoll handoff, and the profiler counts the pause.

## Reproducing

```
python3 .devtools/bin/server_lua.py -f .devtools/bin/profile_server.lua
python3 .devtools/bin/server_lua.py 'return WSProfile.Start(60, WSProfile.ACTIONS)'
python3 .devtools/bin/server_lua.py 'return WSProfile.Report(30)'
```

Experiments B to L were one-off probes run through `server_lua.py`; each
restored what it patched.
