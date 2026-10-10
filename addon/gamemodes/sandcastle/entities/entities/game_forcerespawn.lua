-- game_forcerespawn: respawns players on the map's signal, optionally
-- swapping RED and BLU first (CTFForceRespawn, server/tf/entity_forcerespawn.cpp).
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

-- CTFForceRespawn::ForceRespawn. With a team, only its dead players come back.
function ENT:ForceRespawn(switchTeams, onlyTeam)
	for _, ply in ipairs(player.GetAll()) do
		local team = WS.TeamOf(ply)
		if team ~= WS.TEAM_UNASSIGNED then
			if switchTeams then
				WS.SetPlayerTeam(ply, WS.EnemyOf(team), true)
				team = WS.EnemyOf(team)
			end
			if onlyTeam == WS.TEAM_UNASSIGNED or (team == onlyTeam and not ply:Alive()) then
				ply:Spawn()
			end
		end
	end
	-- Dropped weapons and ammo packs go.
	for _, pack in ipairs(ents.FindByClass("tf_ammo_pack")) do pack:Remove() end
	self:TriggerOutput("OnForceRespawn", self)
end

local INPUTS = {
	forcerespawn = function(self) self:ForceRespawn(false, WS.TEAM_UNASSIGNED) end,
	forcerespawnswitchteams = function(self) self:ForceRespawn(true, WS.TEAM_UNASSIGNED) end,
	forceteamrespawn = function(self, value) self:ForceRespawn(false, tonumber(value) or WS.TEAM_UNASSIGNED) end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
