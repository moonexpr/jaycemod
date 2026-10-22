-- NPCs: the NextBot NPC system, its actor and combatant ports, targeting,
-- and path search on the nav mesh, each loaded the first time it is read.
-- One line a module, never a loop: docs/foundation-game-split-plan.md.
local npc = Namespace("npc")
Defer(npc, "nextbot", "games.npc.nextbot")
Defer(npc, "actor", "games.npc.actor")
Defer(npc, "combatant", "games.npc.combatant")
Defer(npc, "targeting", "games.npc.targeting")
Defer(npc, "astar", "games.npc.astar")
