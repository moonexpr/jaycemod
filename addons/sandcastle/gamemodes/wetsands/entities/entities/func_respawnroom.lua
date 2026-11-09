-- func_respawnroom (CFuncRespawnRoom): a team's spawn room. Its team and
-- active state drive the func_respawnroomvisualizer forcefields that name it;
-- a change of either is told (WSSpawnRoomsChanged).
ENT.Type = "brush"
ENT.Base = "base_brush2"

function ENT:VolumeInit()
	self.originalTeam = self.team
	self.visualizers = {}
	self.active = true
end

function ENT:AddVisualizer(viz)
	self.visualizers[viz] = true
end

function ENT:EachVisualizer(fn)
	for viz in pairs(self.visualizers) do
		if IsValid(viz) then fn(viz) else self.visualizers[viz] = nil end
	end
end

-- CFuncRespawnRoom::SetActive: the room's trigger and its forcefields follow.
function ENT:SetActive(active)
	self.active = active
	self.enabled = active
	self:EachVisualizer(function(viz) viz:SetActive(active) end)
	hook.Run("WSSpawnRoomsChanged")
end

-- CFuncRespawnRoom::ChangeTeam
function ENT:ChangeTeam(team)
	self.team = team
	self:EachVisualizer(function(viz) viz:ChangeTeam(team) end)
	hook.Run("WSSpawnRoomsChanged")
end

function ENT:PointIsWithin(pos)
	return self:WorldToLocal(pos):WithinAABox(self:OBBMins(), self:OBBMaxs())
end

-- CFuncRespawnRoom::InputRoundActivate: a room placed with no team takes the
-- team of an enabled spawn point inside it, as the round has set them up.
function ENT:RoundActivate()
	if self.originalTeam ~= WS.TEAM_UNASSIGNED then return end
	self:ChangeTeam(WS.TEAM_UNASSIGNED)
	for _, spawn in ipairs(ents.FindByClass("info_player_teamspawn")) do
		local s = WS.SpawnState(spawn)
		if not s.disabled and s.team > WS.TEAM_SPECTATOR and self:PointIsWithin(spawn:GetPos()) then
			self:ChangeTeam(s.team)
			return
		end
	end
end

ENT.Inputs = {
	setactive = function(self) self:SetActive(true) end,
	setinactive = function(self) self:SetActive(false) end,
	toggleactive = function(self) self:SetActive(not self.active) end,
	roundactivate = function(self) self:RoundActivate() end,
	setteam = function(self, value) self:ChangeTeam(tonumber(value) or WS.TEAM_UNASSIGNED) end,
}
