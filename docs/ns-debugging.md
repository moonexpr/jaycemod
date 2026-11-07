# NextSoldier: seeing, debugging and tuning the tactics

NextSoldier (NS) is the soldier AI built on NextBot, with its tactical
planning: squads, lanes and battle lines. The AI war is the multiplayer mode
whose PvE runs on it. This is how to see what NS is doing and change its
constants while it plays. Everything here is also on the spawn menu's
**Utilities › Sandcastle › Debug NextSoldier** panel as buttons.

The AI-war commands and convars here exist once the war has started on the
map.
Some names still say `aiwar` (the overlay's command, its layer, the soldier
report and trace, and the modules the tactics live in) until the split in
`docs/ns-split.md`.

NextSoldier's commands and convars are named `ns_<subject>_<verb or
specifier>`: `ns_lanes_print`, `ns_lanes_replan`, `ns_lanes_debug`.

## Seeing: the overlay

`ws_aiwar_debug` (admins) toggles the overlay, the nbdebug feature's
AIWAR layer. Each part of it is the viewer's own client convar, `1` by
default, flipped by the panel's toggles:

| Convar | Draws |
|---|---|
| `ns_soldiers_debug` | each soldier's box (role, action, squad, lane...), route and goal |
| `ns_squads_debug` | a double ring at each squad leader's feet, a link from each member to it (dim while its element holds in a fight), and the squad's summary under the leader: size, contact age, bound (moving element, how many there, time to swap), flank, fall back steps, lane |
| `ns_contacts_debug` | where each squad last saw the enemy, its flank point, a line from each fighting member to the contact, claimed cover |
| `ns_lanes_debug` | each team's lanes, labelled with length and the squads holding them |
| `ns_battlelines_debug` | each team's battle lines (a rail through its posts, ordered across the way they face, or a ring round a KOTH hill), forward posts dimmer, its front (where its lanes lead) as a pillar, and the cart spheres |

`ws_aiwar_debug_full 1` puts the whole action stack in each box. The
NextBot layers (`ws_nb_debug PATH|COST|BEHAVIOR|NAV`, superadmins)
draw with it.

## Debugging: console reports

Admins, while the war runs; printed to your console and the server's.

- `ns_squads_print [RED|BLU]`: each squad's summary, its leader, its
  spread (farthest member from the leader), then each member by place, how
  far it is from the leader and what it is doing. Members past
  `orders.REGROUP_RANGE` are flagged *straggling*.
- `ns_lanes_print`: per team, its front, then each lane's length against
  the shortest, waypoints, the share of its nav areas each other lane also
  takes, and the squads holding it; or why there are none yet (planning, or
  waiting to retry).
- `ns_lanes_replan`: plans every team's lanes again; the old ones stand
  until the new ones are ready.
- `ns_battlelines_print`: per team, its front, its posts' width and depth
  (or ring size), and every squad in contact or falling back.
- `nb_scenarios_reload`: reloads module-backed scenario behavior and
  recompiles the scenario registry without changing maps. When the selected
  scenario is unchanged, its current round state is preserved.
- `ws_aiwar_report`, `ws_aiwar_trace`: every soldier, and one
  soldier's queries and events (unchanged).

## Refining: live tuning

Admins; these keep working after the war ends:

- `ns_tactics_list [word]`: the tactics constants (`foundation.ns.tuning`),
  changed ones first, with their defaults; a word lists those named like it
  (`ns_tactics_list bound`).
- `ns_tactics_tune <name> <value>`: sets one within its range
  (`ns_tactics_tune tactics.BOUND_DISTANCE 400`); `<name> reset` puts it back.
- `ns_tactics_reset`: puts every one back.

A `lanes.*` change plans the lanes again. Values last until the map changes:
once one plays well, write it into its module.

The tunables are the module constants read at each call: `tactics.*`
(contact, bounding, flanking, falling back), `orders.*` (formation spacing,
regrouping, cover, the defenders' rows), `lanes.*` (planning and walking) and
`squad.CLAIM_GRID`. The post scoring constants are not, because posts are
cached per checkpoint.

## Path follower stool

In the toolgun's **NextSoldier** category, **Path Follower** spawns
`npc_pathfollower`, NextSoldier's probe, in one of six models, and drives the
followers selected. Left-click empty ground spawns one (of the panel's team)
and selects it; left-click a follower adds it to or removes it from the
selection (a cyan ring). Reload releases the selection. Spawned followers are
on the player's cleanup list and undone with **Z**.

The panel's **Mode** drives the whole selection its way (`ENT:NSSetDriver`):
switching modes switches what drives the followers, without respawning them.

- **Path** (driver `path`): their bench. Right-click sends them to the aim,
  and later right-clicks change the goal.
- **Local** (driver `legs`): `GroupIdentityBehavior` alone. Right-click gives
  their squad an order at the aim.
- **Tactical** (driver `war`): the AI war's own orders. Right-click reports an
  enemy contact at the aim.
- **Annotate**: marks the map for the war. Followers keep their driver.

**Hold their feet** is one setting for every mode (`NSHoldFeet`, the war
soldier's `NSFeetHeld`): held, a follower plans and draws its path to where
its driver sends it (`ENT:PlanPath`, which `FollowPath` follows) but does not
walk it. Uncheck it and they walk. Out of the war, a tool's follower takes no
damage.

### Path

Followers use active lanes for their team when available, then travel
directly to the clicked goal; without a usable lane they route directly. Their
engine path search uses the same soldier path costs and link rules as combat
soldiers even when the war is inactive, with no extra center-to-center hull
sweep that would reject stair steps. Each model gets a fitted collision hull;
the Tank's large hull can limit which routes it can use. New followers start
**Idle**, switch to **Travel** on a right-click, and return to **Idle** when
they reach the goal. Scout and Headless Hatman use their `Run_MELEE`
animation while moving.

The panel's query checkboxes are what followers on their bench answer the
yes-or-no queries (`nextsoldier.behavior.Responder`), yes when checked and no
when not, a change at once. **Should hurry?** picks its gait: checked it
runs, unchecked it walks. A follower asks only that and **Should attack?**,
and has no weapon to attack with; the others are shown but change nothing, as
only a soldier's chart asks them. Aim at a follower with the tool for its
answers. An errand (`ns_pathfollower_send`) has no responder and runs.

The debug overlay draws the generated path with `PathFollower:Draw()` and
`debugoverlay`, the active lane's waypoints in amber, the clicked goal as a
green sphere, and the local movement command as a thick magenta arrow from
the feet. Console errands (`ns_pathfollower_send`) do not hop toward the raw
goal when their failed search has no reachable waypoint.

### Local

Local mode inspects how members place themselves within a room or enclosed
area: the legs (`GroupIdentityBehavior`) alone, the followers' only tree.
Right-click gives the selected members the panel's order at the aim:
**Muster** (the point, then rings around it), **Fall back** (rows across the
way from you, the threat) or **Assault** (the room at the aim, found by the
war's rooms: the squad stages around the door nearest it, out of the room's
sight, and goes in on its leader's "Move in!", given once all are staged or
`STACK_PATIENCE` after it is). Going in, each runs to an assault point: with no
enemy known, the floor's best by the entrance, off the line in through the
door, the front of the stack first, the rest alternating sides; with an enemy
marked in the room (Annotate's **enemy**, the squad's team), a ring round it,
drawn in where the walls leave too little of it, the points spread over all
the arc the floor covers. Each holds its point until all do and none has met
the enemy for `CLEAR_GRACE`; its leader calls "Room clear!" and each goes on to
its place in the room, filled deepest first. A room with more than one entrance
is taken stealthily: the front is the entrance the most of the squad's team's
incursion flow comes in by (the war's classes, `RoomForSquad`'s `entrances`),
where the member nearest it, the decoy (`LegsDecoy`), hides; the rest split
over the other entrances, walking round the room (its own nav areas kept out
of), and stage there out of its sight. Once they are, the decoy shows itself
`SHOW_OUT` outside the front until it meets the enemy or `DECOY_PATIENCE`
passes, then hides again, and the leader signals the rest in by the sides and
back. Half the squad lost at any part of an assault, its leader calls "Fall
back!" (the first of the living to see the leader lost takes the lead) and all
leave the room to hide out of its sight. Reload dissolves them.
Each member's place shows as a cross, green for muster, orange for fall back
and violet for an assault, and its way there as its path; a member staging
heads for its place in the stack, the white ring. A
place is only where a body fits, with no wall between it and the order's
point (`NSLegsAdmit`). An order skips the places the map refuses and looks
further out, up to three rings or rows past what its members need. A member
left with no place gets a red cross at its own feet. Members furthest from the point choose their
places first, so a straggler keeps to its own side. **Show spacing** draws
each member's spacing ring, pink with an arrow where a teammate pushes it.
That is `engine.Separation`, the same Rust as a bot player's `GroupPush`.

The panel's **Mode** is the squad's mode, one whole number on its order
(`group_identity.MODE`). Each mode is the action members run under their
order's (`nextsoldier.behavior.gib_behaviors`), moving them about the
squad's point and their places, never the point itself. Picking a mode in
the menu sets it on the squad once, so it does not undo the leader's fall back.
**Stationary** (0, `LegsStationary`): each rests, crouched, at a seat near
its place (a nav hiding spot within `REST_RADIUS`, by a wall or in a corner,
that no other member holds), else at its place. **Alert** (1, `LegsPatrol`):
each patrols spots round the order's point on its own side, using
`PATROL_RADIUS` and `PATROL_REST` as the war's defenders do (384 units, 6 s).
**Cautious** (2, `LegsWander`): each wanders near its own place, as attackers
wander in setup (300 units, 12 s). **Panic** (3, `LegsEvacuate`): each runs
from where it stands for the way out of the room furthest from the threat (a
fall back's threat is you; a muster's, its point): the doors of its room
where the AI war has found the map's rooms, else straight away from the
threat; where the order knows its room (`SetRoom`, the war controller's
`RoomForSquad`), past the way out to hide out of the room's sight with cover to
spare, each apart (`Hideout`), not just out of the doorway. **Close** (4, `LegsStayClose`): each stays within `STAY_CLOSE_RANGE`
of the squad's leader (the first picked), and runs back to it when further.
A member that strays more than `REGROUP_RANGE` from the squad's point, while
stationary, alert or cautious, suspends that action for `LegsRegroup` and
runs back to its place.

Members on legs can be hurt; followers on their bench cannot. When a full
squad (a leader and others) has lost half of those it placed
(`CASUALTY_SHARE`), its leader calls the fall back once: "Fall back!" in the
chat and the server's console, and the squad evacuates. A white ring marks
where a member is going now, and its path there is drawn.
A **danger** mark (Annotate) of the squad's team within a room's breadth of
its point (768 units) has its leader call the fall back the same way, and the
squad evacuates away from the mark: an object, or a place in the room. An
evacuating member runs out by its way out and `EXIT_CLEARANCE` past it, clear
of the room. `.devtools/bin/squad_member_check.lua` runs the orders and modes
on a server, kills two of four to see the fall back called, and returns it all
as data.

#### dev_3house: the room bench

`dev_3house` (`.devtools/bin/dev_3house_map.py`, through hammer-mcp) is three
sealed houses on grass: RED's spawn room, the bench (one 768-square room, a
128-wide doorway in each wall, glass windows), and BLU's spawn room. Each spawn
room has twelve starts, a `func_respawnroom`, a resupply locker and its
`func_regenerate`, and at its door a shutter (`func_door`) its team's trigger
opens, behind a `func_respawnroomvisualizer`. The script renders it top-down,
from the side, through the bench's doors and inside a spawn room, and draws
its plan, before it compiles. The nav mesh is built on the server by
`.devtools/bin/dev_3house_nav.lua`, run twice: first it generates the mesh with
the shutters open and the fields passable; after the map reloads, it repairs
it. The generator links a room's floor straight to the grass across a
doorway's threshold (areas that do not touch), which the war's rooms read as
an opening the breadth of the room's side, and lays floor on the windows'
sills, which hides the windows from them. The repair cuts those links, removes
what no walk from the seeds reaches, and saves the mesh, so the bench reads
as a sealed indoor room with four doors and eight windows.

`.devtools/bin/dev_3house_bench.lua` runs five RED followers on their legs,
feet free, through a room operation, stage by stage: spawn, muster (from
RED's spawns, checking the placement: a place each, spaced apart, no two walks
crossing, each resting at its own), mobilize (out through the shutter to the
grass), assault (a decoy at the west door, the rest staged at the north,
south and east doors out of the room's sight, none in before the leader's
signal, then spread over the room), assault_rout (the leader and two more
killed as they go in: the lead taken, the fall back called, the rest hidden),
hold (alert), evacuate (a danger marked on
BLU's side), rout (three of five killed) and remuster. Each stage sets up its
own start, so any one runs alone (`NSRoomBench.Run("evacuate")`) or all in turn
(`RunAll`; a run started ends one still going), and checks its result as data
(`NSRoomBench.Report()`, or one stage in full, passed or not,
`NSRoomBench.Show("muster")`). `.devtools/bin/assault_view.py` draws an
assault's placements and paths from above, with no one moving, for an enemy
marked at the bench's centre, rear, front, left and right
(`NSRoomBench.Placements()`, into `.devtools/artifacts/maps/dev_3house_assault.png`). Like the war, it makes the forcefields
passable: TF2's stop only players, and NextBots' movement takes them for walls.

`.devtools/bin/dev_3house_trial.lua` puts the pieces together against a real
enemy: five RED followers on their legs, armed, leave RED's spawn for the
staging point and are given the assault on the bench; once the first stages,
one BLU follower, armed, with five times a soldier's health, leaves BLU's spawn
for the bench's middle and patrols it. Both fight as the base fights (no aim
error, no reaction time: tf_bot_difficulty's EXPERT). A member lost before the
leader's "Move in!" fails it; then the expert killed wins it, and a fall back
or the squad killed loses it (`NSAssaultTrial.Start()`, `NSAssaultTrial.Report()`:
the log of stages, sightings and kills, and the damage each dealt). A follower
on its legs looks and fires as the war's soldiers do while they walk it, and
walks to within `LEGS_REACH` of its spot, inside the reach they count it
there. An assault keeps its stacks off the entrances the enemy's flow comes in by
(`RoomForSquad`'s `enemyFlow`), where it would meet them on its way in.

An order's places come a group at a time (a muster's rings, a fall back's
rows), whole but for the last, of which it keeps the slots nearest the
members' middle, so a ring partly filled faces the squad coming in. Each
member, the furthest from the point first, takes the slot nearest it, which
sends the front of a file deepest; any two whose walks there cross swap.

### Tactical and Annotate

Tactical mode tests the war's squads under the war's own orders. With no war
running, the first follower put in the war starts a bench war (`Controller:Start{ bench = true }`): the war's models, scenario,
field, orders, lanes and rooms, without the bot quota, the reinforcement
waves, the gameplay request or any other NPC enlisted, so the followers are
the war's only soldiers; it ends with the last of them, removed or driven
otherwise. A war started with `mp_aiwar_start` takes them in instead.
Left-click also selects one of the war's own soldiers, whose feet the setting
holds too. A held soldier's orders run as ever; the target they give it is a
yellow cross. The panel sets the conditions the orders meet: one squad of the
selection, its job, lanes on or off (`fireTeam.lanesOff`: no lane, no muster
along them), missions on or off, a contact reported at the aim
(right-click), a recall to regroup. Reload lets the war's soldiers walk again.

Annotate mode marks the map for the war, by the panel's team. Objectives
are placed as the Gameplay tools place them: control points, spawners and
spawn rooms, flags and capture zones, track nodes, signs. The marks go
through the war's own inputs (`features.aiwar.marks`, `sv_marks.lua`):
a **post** is one of the field's posts for the team; a **rally** is where its
recalled squads regroup; an **enemy** is a contact reported to its squads
while the mark stands; **avoid** closes the areas there to every team, as a
disabled hazard; a **danger** is what its squads on their legs retreat from
(Local, above). A **mission** goes to the selected squads: the room at the
aim and its kind, issued through `Mission.Issue` (`spec.given`). Reload
removes the marks or the piece near the aim.

## Inspecting NextSoldiers

`ws_nb_select <entity index>` can select any live entity derived from
`base_nextsoldier`, including tool-managed path followers. The existing
`ws_nb_debug BEHAVIOR|NAV|PATH|COST` layers then show its behavior state,
nearby nav areas, generated engine path, and the areas considered by its path
cost callback. PATH draws the live engine path while it is enabled for a
NextSoldier, with the goal sphere shown in the viewer's overlay. AI-war
soldiers retain their full action-stack report.
