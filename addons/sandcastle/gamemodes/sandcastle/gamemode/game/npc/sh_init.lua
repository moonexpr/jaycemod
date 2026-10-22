-- NPCs' path search on the nav mesh, each loaded the first time it is read.
-- One line a module, never a loop: docs/foundation-game-split-plan.md.
local npc = Namespace("npc")
Defer(npc, "astar", "game.npc.astar")
