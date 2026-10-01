# NextSoldier: seeing, debugging and tuning the tactics

NextSoldier (NS) is the soldier AI built on NextBot, with its tactical
planning: squads, lanes and battle lines. The AI war is the multiplayer mode
whose PvE runs on it. This is how to see what NS is doing and change its
constants while it plays. Everything here is also on the spawn menu's
**Utilities › Sandcastle › Debug NextSoldier** panel as buttons.

For now NS runs only inside the AI war, whose feature registers these
commands: they exist once the war has started on the map.
Some names still say `aiwar` (the overlay's command, its layer, the soldier
report and trace, and the modules the tactics live in) until the split in
`docs/ns-split.md`.

NextSoldier's commands and convars are named `ns_<subject>_<verb or
specifier>`: `ns_lanes_print`, `ns_lanes_replan`, `ns_lanes_debug`.

## Seeing: the overlay

`wetsand_aiwar_debug` (admins) toggles the overlay, the nbdebug feature's
AIWAR layer. Each part of it is the viewer's own client convar, `1` by
default, flipped by the panel's toggles:

| Convar | Draws |
|---|---|
| `ns_soldiers_debug` | each soldier's box (role, action, squad, lane...), route and goal |
| `ns_squads_debug` | a double ring at each squad leader's feet, a link from each member to it (dim while its element holds in a fight), and the squad's summary under the leader: size, contact age, bound (moving element, how many there, time to swap), flank, fall back steps, lane |
| `ns_contacts_debug` | where each squad last saw the enemy, its flank point, a line from each fighting member to the contact, claimed cover |
| `ns_lanes_debug` | each team's lanes, labelled with length and the squads holding them |
| `ns_battlelines_debug` | each team's battle lines (a rail through its posts, ordered across the way they face, or a ring round a KOTH hill), forward posts dimmer, its front (where its lanes lead) as a pillar, and the cart spheres |

`wetsand_aiwar_debug_full 1` puts the whole action stack in each box. The
NextBot layers (`wetsand_nb_debug PATH|COST|BEHAVIOR|NAV`, superadmins)
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
- `wetsand_aiwar_report`, `wetsand_aiwar_trace`: every soldier, and one
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
