# Places: prior art for room classes, occupation and missions

Research for `docs/places-plan.md`: what games, doctrine, game theory and
graph algorithms already say about classifying the map's spaces, tracking who
holds them, and choosing where to ambush, assault and build. Findings only;
the choices are the architect's.

Where a claim rests on one source I did not open in full, it says so.

---

## 1. Game AI

**TF2 bots: incursion distance is the backbone.** Every `CTFNavArea` holds a
travel distance from each team's *active* spawn room
(`native/vendor/source-sdk-2013/src/game/server/tf/nav_mesh/tf_nav_area.h:81-85`:
`GetIncursionDistance`, `GetNextIncursionArea`, `CollectPriorIncursionAreas`).
It is a flood from a valid `info_player_teamspawn` inside an active,
enabled `func_respawnroom`, recomputed only on `teamplay_point_captured`,
`teamplay_setup_finished`, `teamplay_point_unlocked` and round restart
([tf_nav_mesh.cpp](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/nav_mesh/tf_nav_mesh.cpp),
`FireGameEvent` and `ComputeIncursionDistances`). Area attributes are flags,
partly computed (`TF_NAV_SPAWN_ROOM_RED/BLUE`, `SPAWN_ROOM_EXIT`,
`CONTROL_POINT`, `*_SENTRY_DANGER`) and partly authored (`SNIPER_SPOT`,
`SENTRY_SPOT`, `*_SETUP_GATE`, `BLOCKED_UNTIL_POINT_CAPTURE`, `*_ONE_WAY_DOOR`)
(`tf_nav_area.h:14-58`). Three uses matter here:

- **Ambush.** `ScanSelectAmbushAreas` keeps an area that the enemy reaches
  no later than its incursion distance plus a tolerance (300 units), has a wall
  on at least one side, does *not* see too much incoming enemy floor (summed
  area of visible areas with a lower enemy incursion distance), and lies near an
  "invasion area" the enemy will pass first (`tf_nav_mesh.cpp`, `CollectAmbushAreas`).
  An ambush spot is beside the enemy's flow, covered, and not exposed to
  everything that approaches it.
- **Sentry siting** (engineer `MoveToBuild`): areas that see the point,
  and on KOTH only those where `incursion(mine) < incursion(enemy)`: "ignore
  areas the enemy can reach first"
  ([tf_bot_engineer_move_to_build.cpp](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/bot/behavior/engineer/tf_bot_engineer_move_to_build.cpp)).
  That comparison is a territory line with no occupation model at all.
- **A caveat in the code**: a disabled branch is commented "incursion flow is
  badly behaved at cap #1, stage #2 in dustbowl". Single-source distances fail
  on multi-stage maps when spawns move.

**CS:S bots: places are labels, and tactics are per-spot.** A Place is a
designer-painted name from a preset list (`nav_use_place`), used for radio
callouts and the radar, not computed
([VDC: Nav edit](https://developer.valvesoftware.com/wiki/Nav_edit),
[Place names](https://developer.valvesoftware.com/wiki/Place_names)). The
computed tactics are hiding spots flagged `IN_COVER`, `GOOD_SNIPER_SPOT`,
`IDEAL_SNIPER_SPOT`, `EXPOSED`, and `SpotEncounter`s: for each way through an
area, the spots to look at in order (`nav_area.h:111-129, 186-200`). Our
converted meshes have no places (`rooms.lua` header), which is why rooms exist.

**Left 4 Dead: flow distance and the active area set.** Flow distance is
"travel distance from the starting safe room to each area"; it answers "is this
spot ahead or behind the Survivor group". The Active Area Set is the set of nav
areas around the survivors, where the director creates and destroys population;
"Potentially Visible Areas" is a second set
([Booth 2009, slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)).
It is the same single-source distance as TF2's, put to "ahead/behind" questions.

**Killzone (2004): position evaluation.** Positions are scored by a configurable
weighted sum of annotations: line of fire to the primary threat (40 with partial
cover, else 20), cover from secondary threats (20), range, proximity. Suppression
fire is "evaluate threat's attack positions from his perspective; select those
attack positions we can fire into"
([Beij & Straatman, GDC Europe 2005](https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf)).
This is a within-room tool (posts), not a room classifier.

**Killzone 2 multiplayer bots.** Waypoints are grouped by hand into `AIArea`s,
"most commonly used to name certain locations, e.g. a certain room" (§3.1.3). The
faction commander picks targets in order: already-targeted ones (to avoid
swapping), then neutral, then enemy-held, preferring those nearer the best spawn,
and abandons a target only when its count of failed attacks differs by more than
10 "to prevent twitching" (§5.1.2). Playtesters' main complaint: bots "did not
seem to have any notion of chokepoints or entry locations"; "humans would defend
the chokepoints to an objective area before the actual objective itself" (§6).
The author proposes storing each objective's entry points as its "defense
perimeter" (§7.4.6)
([Verweij 2007](https://www.guerrilla-games.com/media/News/Files/VUA07_Verweij_Hierarchically-Layered-MP-Bot_System.pdf)).

**Halo 3: territory belongs to tasks.** A task is "the mission designers' language
for telling the AI what it should be doing": a territory plus behaviour. Squads
are poured into a prioritised task tree; distribution respects task capacities
(bin packing, NP-hard, done approximately) and minimises a cost H(F): travel, coordination,
balance, nearness to the player
([Isla, GDC 2008 slides](https://web.cs.wpi.edu/~rich/courses/imgd4000-d09/lectures/halo3.pdf)).
Territories are authored, not computed.

**F.E.A.R.**: its squad layer coordinates behaviours (suppression, advancing
cover) over the planner ([Orkin 2006](https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf)).
I found insufficient evidence that it classified space; it is not a source for
this layer.

**StarCraft map analysis.** BWTA builds regions from a pruned Voronoi diagram of
walkable terrain and puts chokepoints on region boundaries; its chokes matched 97%
of those people picked ([Perkins 2010](https://ojs.aaai.org/index.php/AIIDE/article/view/12405);
faster contour-tracing successor [BWTA2](https://ojs.aaai.org/index.php/AIIDE/article/view/12889)).
BWEM gives each tile an "altitude" (distance to unwalkable), grows areas from the
highest altitude down, and puts chokes where areas meet
([BWEM FAQ](https://bwem.sourceforge.net/faq.html)). `rooms.lua`'s clearance cores
are this same idea: a distance-to-wall field, cores at wide floor, boundaries at
narrows.

**Level design patterns.** Hullett & Whitehead catalogue FPS patterns including
sniper location, gallery, choke point, arena and stronghold, with their effects on
play ([Hullett, *The Science of Level Design*](https://escholarship.org/uc/item/1m25b5j5)).
Their names line up with ours (overlook ≈ sniper location/gallery; common ≈
arena), but I did not read their stronghold definition, so I can't compare it to ours.

## 2. Military terrain analysis

**OAKOC.** FM 3-21.8 lists observation and fields of fire, avenues of approach,
key and decisive terrain, obstacles, cover and concealment, and suggests the order
obstacles, then avenues, then key terrain, observation, cover (para 5-30). "Key terrain
affords a marked advantage to the combatant who seizes, retains, or controls it",
is identified "starting at the objective ... working backwards", and "is a
conclusion rather than an observation"; high ground "easily bypassed, is not key
terrain"; decisive terrain is key terrain whose control is necessary for the mission
(para 5-33)
([FM 3-21.8, 2007](https://usu.edu/military-science/files/tools-for-cadets/the-infantry-rifle-platoon-and-squad.pdf);
superseded by ATP 3-21.8, 2024 edition not checked). Mapping:

| OAKOC | Our model |
|---|---|
| Obstacles | the graph's edges and what blocks them: func_doors, setup gates, unbroken windows, one-way doors (§2.1) |
| Avenues of approach | lanes through rooms; thoroughfares (§2.3, §3) |
| Key terrain | not a static class: rooms whose holding decides the objective, derived backwards from objective rooms (their entry rooms, their overlooks) |
| Observation and fields of fire | overlook (§2.3) |
| Cover and concealment | within a room: posts, not places |

**Ambush.** "The kill zone must be covered entirely by fire"; formations are
linear (parallel to the route, the enemy held on the long axis), L-shaped (long leg
parallel, short leg enfilading, "at a sharp bend"; not where the short leg would
cross a straight road) and V-shaped (paras 7-119, 7-125, 7-130 to 7-132, FM 3-21.8).
Doctrine and TF2's `ScanSelectAmbushAreas` agree: the ambushers stand *beside* the
route, not in it.

**Urban entry.** "The door is the focal point of anyone in the room. It is known as
the fatal funnel"; the team moves through without stopping, the first man deep into
a corner ([FM 3-06.11, 2002, para 3-21](https://archive.org/download/milmanual-fm-3-06.11-combined-arms-operations-in-urban-terrain/fm_3-06.11_combined_arms_operations_in_urban_terrain.pdf)).
Read for us: a defended room's doors are its kill zones (supports §4's ambush
"door the enemy comes in by"), and an assault through the door the defenders
watch is the expensive option.

**Siting a base.** The patrol base criteria: terrain "the enemy would probably
consider of little tactical value", "off main lines of drift", defensible for a short
time, with cover; avoid known enemy positions, roads and trails; always plan an
alternate site and a withdrawal route
([Ranger Handbook SH 21-76, 2000, §5-5](https://www.atu.edu/rotc/docs/3_21-76_Ranger_HB.pdf);
current [TC 3-21.76](https://irp.fas.org/doddir/army/tc3-21-76.pdf) not checked).
Rally points: "away from natural lines of drift", "defendable for short periods"
(FM 3-21.8 para 9-43).

**Disagreement to resolve.** places-plan.md §4 puts the remote base "on its
lanes ... ordered by how far forward". The patrol-base doctrine puts it *off*
lines of drift (low traffic, low betweenness). TF2's engineer puts its nest where
the team arrives first. A remote base in our sense (a forward spawn and support)
is closer to TF2's than to a hidden patrol base, but the doctrine's "off the main
lines of drift, near a route" is a cheap filter worth weighing. The architect
decides.

## 3. Game theory

- **Network interdiction** ([Washburn & Wood 1995](https://ideas.repec.org/a/inm/oropre/v43y1995i2p243-251.html)):
  an evader crosses a network, an interdictor inspects arcs; optimal strategies are
  mixed and computed with network-flow methods in polynomial time. My reading is
  that with equal detection on every arc, the interdictor plays uniformly over a
  minimum cut. I could not open the paper to check this. Usable rule: **ambush
  candidates are the doors of a minimum cut between the enemy's spawn rooms and the
  objective, chosen at random among them.**
- **Patrolling games** ([Alpern, Morton & Papadaki 2011](https://eprints.lse.ac.uk/32210/))
  and **Stackelberg security games** (ARMOR at LAX,
  [Pita et al. 2009](https://ojs.aaai.org/index.php/aimagazine/article/view/2173)):
  the defender randomises so an observing attacker cannot exploit a pattern.
  Solving them exactly is too much for us. The cheap part to take is the
  randomisation: **draw among the top few candidates weighted by score, never always
  the best.** Human players learn a fixed bot pattern within a few rounds.
- **Colonel Blotto** ([Roberson 2006](https://ideas.repec.org/a/spr/joecth/v29y2006i1p1-24.html)):
  allocating forces over several fronts has no pure equilibrium, and (as I read
  later summaries) the weaker side leaves some fronts empty and concentrates on the
  rest. Usable rule: **an outnumbered team chooses fewer missions and does not spread
  over every lane.** For the allocation itself, Halo 3's greedy, capacity-limited
  assignment with a cost function is the practical form.
- **Pursuit-evasion / cops and robbers** (e.g. Nowakowski & Winkler 1983, not
  checked here): one searcher clears a tree, and cycles need more. It bears on clearing a
  dead-end branch (`hunt`, `explore`) more than on places. Low value for this plan.
- **Territory control**: I found no game-theory model better than the game-AI
  practice (Voronoi by travel distance, influence frontiers). Insufficient evidence.

## 4. Spatial algorithms

**Segmentation.** Recast's default watershed partitions on a distance field
([Recast](https://recastnav.com/RecastRegion_8cpp.html)); the robotics room
segmentation survey compares morphological, distance-transform, Voronoi and
feature methods on 20 floor plans
([Bormann et al., ICRA 2016](https://ieeexplore.ieee.org/abstract/document/7487234));
secondary sources report Voronoi-graph segmentation as the most stable. Rooms exist
already; no new segmentation is needed for this layer.

**Centrality.** Space syntax measures exactly what §2.1 proposes: *depth* (steps
from a root in a justified graph), *integration* (mean depth to all others, i.e.
closeness), *choice* (shortest paths through a space, i.e. betweenness), and links
integration to movement ([overview](https://en.wikipedia.org/wiki/Space_syntax);
[Hillier legacy review](https://doi.org/10.3390/su13063394)). Shortest-path
betweenness is O(VE) by Brandes's algorithm
([Brandes 2001](https://doi.org/10.1080/0022250X.2001.9990249)). Restricted to a
few key pairs (spawns to objectives) it is brittle: one shortest path takes all the
credit and a near-equal alternative gets none. Current-flow (random-walk)
betweenness spreads credit over all routes by their resistance
([Newman 2005](https://arxiv.org/abs/cond-mat/0309045)). The sources disagree on
which predicts movement better. Our soldiers follow lanes with
penalised flanks, so counting rooms over the planned lanes may beat both.

**Cuts.** Articulation points and bridges in O(V+E)
([Hopcroft & Tarjan 1973](https://doi.org/10.1145/362248.362272)): a branch hanging
off an articulation point with no key room in it is a dead end, and its size is its
depth. A minimum vertex cut between two teams' spawns gives the fewest doors that
separate them (KZ2's "entry points"). The plan's stronghold definition needs no cut:
it is a reachability test.

**Influence maps.** Sources stamp influence, propagate it with decay per step, and
read the frontier where the sign changes; double-buffer the update
([Champandard](https://www.gamedev.net/articles/programming/artificial-intelligence/the-core-mechanics-of-influence-mapping-r2799);
[Mark, Game AI Pro 2 ch. 30](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter30_Modular_Tactical_Influence_Maps.pdf)).
On a room graph, propagation through doors avoids the grid's leak through walls.
Caution: propagating from the *truth* leaks knowledge; per the plan, a team's map
must be fed from its own intel.

**Hysteresis.** All three games damp change. TF2 recomputes only on discrete
events, KZ2 needs a margin of 10 failed attacks, Halo moves squads by task changes.
The plan's `HOLD` plus a margin is one threshold. A Schmitt trigger (take at a high
threshold, lose at a lower one) plus a minimum dwell time is the standard fix.

## What to take

Costs are for 20 to 200 rooms and roughly twice as many edges, in LuaJIT on the
slow lane.

1. **Per-team incursion distance over the room graph.** Dijkstra from each team's
   active spawn rooms, recomputed on the same events TF2 uses (capture, setup
   finished, point unlocked, round reset, respawn-room I/O). It answers "ahead or
   behind", orders "how far forward", and gives a territory line before any presence.
   Plugs into §2.1 (measure) and §2.2 (the spawn claim's reach). Cost O(E log V) per
   team, under a millisecond. Sources: `tf_nav_area.h:81`, Booth 2009. Check
   multi-stage maps (the dustbowl comment).
2. **Frontier as `incursion(own) < incursion(enemy)`, refined by occupation.** It
   is TF2's KOTH sentry rule. It gives frontier and stronghold candidates on a round's
   first tick and a fallback when occupation is thin. §2.3. O(V).
3. **Stronghold by reachability.** Flood from every room the team does not hold,
   never entering rooms it holds; its held rooms not reached are strongholds. §2.3.
   O(V+E) per occupation change. Source: the plan's own definition; no min-cut needed.
4. **Dead end and depth from articulation points.** A branch off an articulation
   point with no key room is a dead end; its depth is its distance from the cut
   room. §2.1/§2.3. O(V+E) once a map. Hopcroft & Tarjan.
5. **Thoroughfare from flow over routes, not single shortest paths.** Either count
   the team's lanes (main, flanks, tours) through each room, or use current-flow
   betweenness between spawn and objective rooms (one Laplacian solve, about 200³
   operations, once a map). Normalise by floor as planned. §2.1/§2.3. Brandes; Newman.
   The sources disagree on which predicts movement better.
6. **Entry doors as a class attribute of objective rooms.** For each objective room,
   the doors of the minimum cut from the enemy's spawn rooms: defenders hold these,
   not the point. Assaults and ambushes read them too. §2.3, §4. Max-flow on unit
   capacities, trivial at this size. Sources: Verweij §6, §7.4.6; Washburn & Wood.
7. **Ambush beside the route, not in it.** Choose the room *adjacent* to a high-traffic
   thoroughfare on the enemy's route, with a door or window onto it, and not overlooked
   by the enemy's approach. Its kill zone is the enemy's door into the thoroughfare.
   Drop "dead ends" from ambush unless an objective lies in one: by definition little
   passes through them. §4. O(V). Sources: `ScanSelectAmbushAreas`; FM 3-21.8 7-130/131.
8. **Assault: avoid the watched door.** Prefer a way in the team's intel has not
   seen covered (a second door, a window, a stairwell from above) over the nearest
   one; when there is a single way in, the room costs more. §4. Source: FM 3-06.11
   3-21.
9. **Remote base: forward but off the drift.** Keep the plan's frontier/held/few-ways
   filter, and add low thoroughfare score and an alternate site. Architect's call
   (§2 above). §4. Sources: Ranger Handbook §5-5; TF2 engineer.
10. **Hysteresis everywhere occupation changes.** Two thresholds (take, lose), a
    minimum dwell, and lanes re-planned only when a room's *class* changes and stays
    changed. §2.2, §3. Sources: KZ2 §5.1.2; TF2 event-driven recompute.
11. **Randomise mission choice among the top few.** Weighted draw over the best 2 or
    3 candidates (the plan's `math.weighted`), and an outnumbered team takes fewer
    missions. §4. Sources: ARMOR; Roberson.
12. **Key terrain is derived, not a class to label up front.** Work backwards from
    objective rooms (their entry rooms and overlooks) and mark those, instead of
    looking for high or central rooms in general. §2.3. FM 3-21.8 5-33.

**Not suited to us:** grid influence maps (the room graph already does the job, and
grids leak through walls); exact Stackelberg/Blotto solvers (too heavy for the gain
against a handful of rooms); Voronoi re-segmentation (rooms exist); Killzone-style
per-position scoring at the room level (it belongs to posts within a room).
