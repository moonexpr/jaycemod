-- NPCs: the NextBot NPC system, its actor and combatant ports and
-- targeting, each loaded the first time it is read (path search on the nav
-- mesh is foundation.wetsands').
-- One line a module, never a loop: docs/foundation-game-split-plan.md.
local npc = Namespace("npc")
Defer(npc, "nextbot", "games.npc.nextbot")
Defer(npc, "actor", "games.npc.actor")
Defer(npc, "combatant", "games.npc.combatant")
Defer(npc, "targeting", "games.npc.targeting")
