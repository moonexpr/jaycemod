-- A hit an attacking player dealt (ws/sv_hits.lua), told to that player
-- alone for its damage number, hit sound and crit text (ws/cl_hits.lua).
local E = WS.Events

local KIND_BITS = 2 -- foundation.players' HIT_*

-- pos: where the number rises from, the top of the victim.
E.Define("game_combat_text", {
	victim = E.Entity(),
	amount = E.Float(),
	kind = E.UInt(KIND_BITS),
	pos = E.Vector(),
})
