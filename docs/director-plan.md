# The war's director: Left 4 Dead's pacing in the tactics engine

**Status: paused (2026-10-27) while what already works is optimized. The
operator's answers (§6) replace §3 to §5 where they differ; the design is
to be redone from them. Nothing below is built.**

The operator's request (2026-10-27): "next up for the tactics engine... we
will begin work on incorporating the same director tech as left4dead2."
The director belongs to the tactics engine (`gamemode/wartactics/`): it is
strategy over soldiers, not a soldier (NextSoldier stays unaware of it).

## 1. What Left 4 Dead's director is

From Michael Booth, *The AI Systems of Left 4 Dead* (AIIDE 2009,
steamcdn-a.akamaihd.net/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf).
Two goals, two mechanisms.

**Adaptive dramatic pacing** ("algorithm adjusts pacing, not difficulty:
amplitude is not changed, frequency is").

- *Survivor intensity*, one number per survivor. It rises when the survivor
  is hurt (in proportion to the damage), is incapacitated, is pulled or
  pushed off a ledge, or when an infected dies near them (inversely with
  distance). It decays toward zero over time, but **not while infected are
  actively engaging them**.
- The team's intensity (the highest of its survivors') drives four phases:
  - **Build up**: full threat population until intensity crosses the peak
    threshold.
  - **Sustain peak**: keep it full for 3 to 5 s more, a minimum build-up.
  - **Peak fade**: minimal population, and wait until intensity decays
    out of the peak range, so the fight in hand plays out without using up
    the relax period, which starts only at a natural break in the action.
  - **Relax**: minimal population for 30 to 45 s, or until the survivors
    have travelled far enough toward the next safe room; then build up.

**Procedural population** ("structured unpredictability": population
functions whose time and place vary by a designer-set amount).

- *Flow distance*: travel distance from the start to each nav area. The
  *escape route* is the shortest path start to exit. Flow answers "is this
  spot ahead of or behind the team?"
- *Potential visibility*: which areas may be seen from which.
- *Active area set (AAS)*: the areas around the survivors; the infected
  exist only there.
- *Wanderers*: a count per area, rolled at map start from escape-route
  length and density; spawned as an area enters the AAS, removed as it
  leaves, zeroed when an area becomes visible to a survivor or while the
  director relaxes.
- *Mobs*: 20 to 30 at a randomised interval (90 to 180 s on Normal),
  spawned in AAS areas out of sight: behind the team's flow (75 % of them,
  since wanderers and specials engage ahead), ahead, near a Boomer's
  victim, or anywhere as the fallback.
- *Specials*: individuals with abilities that harass the team, on their
  own timers.
- *Bosses*: every N units along the escape route, ± a random amount, at
  map start; Tank, Witch and Nothing shuffled and dealt, never one twice
  running.
- *Items*: the designer places candidate weapon caches and item groups; the
  director chooses which exist.

**Left 4 Dead 2** exposes the same director to map scripts (VScript
`DirectorOptions`: mob interval and size, relax threshold and duration,
sustain-peak time, special limits and respawn interval, a locked tempo),
and adds scripted panic and finale stages. These names are from memory:
the Valve Developer Wiki page could not be fetched (a bot check). Check
them before relying on any.

## 2. What the war already has

| L4D | Sandcastle today |
|---|---|
| Flow distance, escape route | `wetsands.navsearch.Distances(mesh, starts, limit, limits[, told])`: walk distance over the mesh snapshot from a set of start areas, native on a server. TF2's per-team incursion distance (`CTFNavArea::GetIncursionDistance`) is the same idea; GMod's nav has none, so guard posts use distance from base as its stand-in (`features/aiwar/sv_posts.lua`). |
| AAS | Nothing by that name. `wartactics.zone` floods the mesh from spawn areas up to the setup gates; `nextsoldier.vision` knows what a soldier sees. |
| Mobs | Respawn waves (`features/aiwar/sv_enlist.lua`, TF2's `GetRespawnWaveMaxLength`) and the reserve of fallen soldiers they revive (`features/aiwar/reserve.lua`). Reinforcements enter at team spawns, or spawn bases on maps without them (`features/aiwar/spawns.lua`). |
| Pacing | None. The Commander (`features/aiwar/scenario.lua`) sets each team's stance per mode, damped by `ALLOCATION_HOLD`; nothing reads how hard the humans are pressed. |
| Specials, bosses | Gadgets, medics and engineers (`docs/engineers-plan.md`); the haunting bosses (`features/haunting`). |
| Items | TF2's map-placed pickups. |

## 3. The design

The director is a model in the tactics engine: pure Lua over ports, each
part a value it is handed, tested under LuaJIT with no game.

1. **`wartactics.intensity`**: a player's intensity, a value decaying at a
   rate unless engaged. Events in: hurt (damage), downed, killed, an enemy
   killed near them (distance). Read: `Of(player)`, the team's (highest).
   Clock and the engaged test are passed in.
2. **`wartactics.pacing`**: the four phases as a `generator.state_machine`
   over the team's intensity and flow travelled: `BUILD_UP`,
   `SUSTAIN_PEAK`, `PEAK_FADE`, `RELAX`, with its thresholds and times
   (`T.defined` in tests, never pinned). It answers "full or minimal
   population now?" per side the humans fight.
3. **`wartactics.flow`**: a team's flow over the mesh, from
   `wetsands.navsearch.Distances` from its spawn areas toward the
   objective: an area's flow, a group's flow (the furthest of its
   members, as L4D's), ahead or behind. Computed once a round (and on a
   forward spawn), off the tick (`feedback-main-thread-free`).
4. **`wartactics.director`**: the composition. Each think it reads the
   phase and turns it into the war's verbs:
   - the waves: the opposing team's respawn-wave interval and size, longer
     and smaller in relax, as L4D's mob interval;
   - the Commander's stance: push in build up, hold in relax (the stance
     damping already exists);
   - where reinforcements enter: behind or ahead in flow, out of every
     human's sight (only if §5.2 allows it);
   - later verbs: specials (gadgets, engineers) and the bosses along the
     escape route.

The controller part is `features/aiwar/sv_director.lua`, wiring game
events (damage, deaths, downs) into `intensity` and the director's
answers into the waves and the Commander. Intensity rises and decays on
events and a cheap per-second step, so the director adds little to the
tick.

## 4. Phases

Each ships alone, tests first, and keeps `check_lua.sh` green.

- **D0. Flow.** `wartactics.flow` on `wetsands.navsearch.Distances`;
  `ns_flow_debug` draws it. Check on pl_upward, koth and a CTF map.
- **D1. Intensity.** `wartactics.intensity` and the events that feed it;
  `ns_director_print` shows each human's intensity. No behaviour changes.
- **D2. Pacing.** `wartactics.pacing`'s phases, printed and logged against
  intensity over a real round, before they drive anything.
- **D3. Waves and stances.** The director drives the opposing waves and
  the Commander's stance. The first change players feel; tuned in game.
- **D4. Placement.** Reinforcements enter behind or ahead out of sight,
  if §5.2 allows.
- **D5. Specials and bosses** as director verbs.

## 5. Questions for the operator

1. **Whose intensity?** L4D paces four survivors against an infected
   side. The war has humans on either side, fighting beside soldiers.
   Does the director pace each human's opponents (both sides, by the
   humans on each), or only the soldier side against the humans (a PvE
   reading, as MvM)?
2. **Spawning out of sight.** L4D spawns mobs anywhere out of sight.
   TF2's maps give each team spawn rooms and the war keeps to them. Is
   placing reinforcements by flow (ahead or behind, unseen) allowed, or does
   the director only pace waves and stances at the spawns?
3. **Which modes first?** Payload and MvM have an escape route by nature
   (a track, a path to the hatch). KOTH and CTF are symmetric. Start with
   payload (pl_upward, the bench map)?
4. **L4D2's script interface.** Expose the director's settings to maps or
   addons as L4D2's `DirectorOptions` (a registry, compiled at the game's
   beginning as the scenarios are), or keep them as convars for now?

## 6. The operator's answers (2026-10-27)

1. **Intensity is the director's own score**, not a player's stress: the
   director optimizes for the most frags, and the most stylish ones (an
   assisted kill counts for more).
2. **The director is a military commander, not a dungeon master**, with
   two hats:
   - it chooses each squad's mission: the objective, pushing the line
     back, or spawncamping the other team;
   - it tunes spawn rates: a team being rolled gets shorter respawn times,
     the team rolling it longer.
   It favours neither team: its goal is the most frags, with tug-of-war
   conditions kept. A stalemate is heavily penalized, and the round must
   still be settled properly before it ends.
3. **CTF first**, with new gameplay pieces such as support units.
4. **No script interface** (L4D2's `DirectorOptions`) for now.
