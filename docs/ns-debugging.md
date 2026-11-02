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
`npc_pathfollower` entities using one of six selectable models. Left-click
empty ground to spawn and select a follower; left-click an existing tool
follower to add or remove it from the selection. Right-click sends every
selected follower to the position, and later right-clicks change that goal.
Reload clears the selection. Followers use active lanes for the tool user's
team when available, then travel directly to the clicked goal; without a
usable lane they route directly. Their engine path search uses the same
soldier path costs and link rules as combat soldiers even when the war is
inactive, with no extra
center-to-center hull sweep that would reject stair steps. Each model gets a
fitted collision hull; the Tank's large hull can limit which routes it can
use.
New followers start **Idle**, switch to **Travel** on a right-click, and
return to **Idle** when they reach the goal. Spawned followers are added to
the player's cleanup list and can be undone with **Z**.
Scout and Headless Hatman use their `Run_MELEE` animation while moving.

The always-on debug overlay draws the current generated path in thick cyan
lines, the active lane's waypoints in thicker amber lines, the clicked goal
in green, and the local movement command as a thick magenta arrow from the
feet.

## Inspecting NextSoldiers

`ws_nb_select <entity index>` can select any live entity derived from
`base_nextsoldier`, including tool-managed path followers. The existing
`ws_nb_debug BEHAVIOR|NAV|PATH|COST` layers then show its behavior state,
nearby nav areas, generated engine path, and the areas considered by its path
cost callback. AI-war soldiers retain their full action-stack report.
