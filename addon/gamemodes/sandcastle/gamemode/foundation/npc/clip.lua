-- Which clip brushes the AI war's soldiers stand on. Maps made for players
-- (TF2's, CS:S's) close gaps and drops with player clips (CONTENTS_PLAYERCLIP)
-- that NPC movement (MASK_NPCSOLID) passes through: arena_well's gap round
-- its point, pl_goldrush's second stage. The soldiers stand in for players
-- there, so they take the player's clips (PLAYER: MASK_PLAYERSOLID); on any
-- other map, made for NPCs, the NPC's (NPC: MASK_NPCSOLID). A map is a
-- players' map by its entities (PLAYER_MAP_CLASSES).
local ipairs = ipairs
module(...)

PLAYER, NPC = "player", "npc"

PLAYER_MAP_CLASSES = {
	tf_gamerules = true,
	info_player_teamspawn = true, -- TF2's team spawns
	info_player_terrorist = true, -- CS:S's
	info_player_counterterrorist = true,
}

-- The clips for a map with entities of these classes (a list of names).
function For(classes)
	for _, class in ipairs(classes) do
		if PLAYER_MAP_CLASSES[class] then return PLAYER end
	end
	return NPC
end
