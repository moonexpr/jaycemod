-- foundation's path search for NPCs. The rest of npc/ is gameplay, bound
-- for game/ and loaded on demand until then. One line a module, never a
-- loop: docs/foundation-game-split-plan.md.
local npc = Namespace("npc")
Export(npc, "pathfinder", require("foundation.npc.pathfinder"))
