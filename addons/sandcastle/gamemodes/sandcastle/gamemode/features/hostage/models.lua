-- The hostages' models: the npc_civilian models of the TF2 Classified
-- Civilian addon the server downloads (3172805326, hostage_civilian in
-- .devtools/bin/server_root.py SERVER_DOWNLOADS), its friendly civilians, one
-- a team colour. They animate as an NPC's; the player models do not.
module(...)

CIVILIAN = {
	"models/player/team/fortress/npc_arces_red_civilian.mdl",
	"models/player/team/fortress/npc_arces_blue_civilian.mdl",
	"models/player/team/fortress/npc_arces_green_civilian.mdl",
	"models/player/team/fortress/npc_arces_yellow_civilian.mdl",
}

function All()
	return CIVILIAN
end

-- The model for a number the caller draws, wrapping past the last.
function Pick(n)
	return CIVILIAN[(n - 1) % #CIVILIAN + 1]
end
