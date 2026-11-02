# Combat repath optimization handoff

## Symptom and current state

Combat path repaths have been reported to stall for about one second. The
affected AI-war player bots plan synchronously: `BotSoldier:Steer` calls
`ws_bot_navigator:PlanRoute`, which calls the engine's `Path:Compute` with
`BotSoldier:RouteCost` as its cost callback.

Commit `872b6f42` added agent-hull clearance checks to route costs. A new
clearance object was originally created for every repath, causing repeated
`TraceHull` checks. Commit `59af16ac` now shares area and link clearance
results across repaths with the same hull and trace configuration, and clears
them when the nav mesh's links are rebuilt by `WS.BridgeNavGaps`.

The cache optimization passed the WS and war suites (2,010 tests), but it has
not yet been profiled on the live server. Treat the one-second stall as a
reported symptom, not as a measured duration after the cache change. The
first search for a hull/mesh still populates its cache, and the engine search
and other route-cost work remain synchronous.

## Measure the actual path before choosing an algorithm

Instrument the AI-war player-bot path specifically, around
`ws_bot_navigator:PlanRoute` and the `RouteCost` callback. Record sampled
compute duration, callback count/time, clearance area/link cache hits and
misses, and actual `TraceHull` count/time. Report cold-cache and warm-cache
repaths separately, plus percentiles and maximum duration.

The existing `ws_path_profile` / `ws_path_bench` in `features.npc.sv_profile`
profiles controller-managed NextBots, not the AI-war player bots whose
navigator is `ws_bot_navigator`; it is not sufficient evidence for this
symptom. Do not run `ws_path_bench` during play: it intentionally performs
back-to-back synchronous searches and stalls the server.

Keep instrumentation bounded and low overhead. Reproduce the same route
multiple times to distinguish one-time cache population from repeated work,
and compare routes with different hulls and edge counts. Preserve each bot's
collision-hull behavior when comparing results.

## Optimization questions

1. If warm searches still spend significant time in `TraceHull`, identify
   which clearance queries miss and why before changing storage or adding a
   spatial broadphase. Any broadphase must preserve collision-hull correctness
   for irregular nav polygons, crouched hulls, and changed meshes.
2. If callback time dominates after cache hits, profile the remaining
   per-edge checks in `RouteCost` and reduce repeated work only where its
   invalidation conditions are explicit (for example blocker generation,
   team, hull, or mesh changes).
3. If the callback is cheap but `Path:Compute` still dominates, compare a
   suitable graph-search path against the engine search on captured routes.
   Preserve ladders, jumps, path segments, and movement semantics; use
   existing route/search implementations where appropriate.
4. Consider Rust only after measurements show algorithm or data-structure
   overhead is material. Rust cannot perform GMod's `util.TraceHull`; keep
   engine collision queries on the engine side or consume safely
   precomputed verdicts.

Validate optimizations against cold and warm repaths, varied hull sizes, and
route correctness, with a stated target for maximum synchronous stall. Avoid
using map regeneration as a prerequisite for performance experiments; these
clearance changes concern path computation over the existing mesh.
