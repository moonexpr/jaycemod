-- The hostages' models, from two Workshop addons the server downloads
-- (.devtools/bin/server_root.py SERVER_DOWNLOADS):
--   hostage_civilian     3172805326, TF2 Classified's Civilian, one NPC model
--                        a team colour
--   hostage_fem_civilian 886058416, Maxxy's TF2 Female Civilian
local ipairs = ipairs
module(...)

MALE = {
	"models/player/team/fortress/npc_arces_red_civilian.mdl",
	"models/player/team/fortress/npc_arces_blue_civilian.mdl",
	"models/player/team/fortress/npc_arces_green_civilian.mdl",
	"models/player/team/fortress/npc_arces_yellow_civilian.mdl",
}

-- fem_civilian_flexible also moves the skirt's bones, and is GMod's.
FEMALE = {
	"models/player/hwm/fem_civilian.mdl",
	"models/player/hwm/fem_civilian_flexible.mdl",
}

local all

-- Every model, male first.
function All()
	if not all then
		all = {}
		for _, list in ipairs({ MALE, FEMALE }) do
			for _, path in ipairs(list) do all[#all + 1] = path end
		end
	end
	return all
end

-- The model for a number the caller draws, wrapping past the last.
function Pick(n)
	local models = All()
	return models[(n - 1) % #models + 1]
end
