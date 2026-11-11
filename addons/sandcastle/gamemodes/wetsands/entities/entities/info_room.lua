-- info_room: a mapper's word on the room it stands in, which the AI war finds from the nav mesh
-- (wartactics.rooms): its name (label), what it is for (class: restricted, stronghold, outpost,
-- highway, commons, unoccupied or wilds), who holds it (TeamNum), and a team_control_point whose
-- owner holds it (controlpoint, over TeamNum). The war reads them as it classes the rooms
-- (features/aiwar/sv_room_hints.lua, wartactics.room_hints); what one leaves out is the war's to
-- find. Keyvalues only: the map's word is read as it loads.
ENT.Type = "point"
ENT.Base = "base_point"

local KEYS = { ["label"] = "label", ["class"] = "class", ["controlpoint"] = "point" }

function ENT:KeyValue (key, value)
	key = string.lower (key)
	if KEYS [key] then
		self [KEYS [key]] = value
	elseif key == "teamnum" then
		self.team = tonumber (value)
	end
end

function ENT:UpdateTransmitState ()
	return TRANSMIT_NEVER
end
