-- func_respawnroomvisualizer (CFuncRespawnRoomVisualizer): the forcefield
-- over a spawn room's doors. At round start it takes its func_respawnroom's
-- team; the room's SetActive switches it on and off. It stops the enemies of
-- its team, shows itself only to them while its room is active, and opens
-- for everyone during team win and out of gameplay.
-- It is an "anim" entity rather than "brush" so clients can draw it.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "RoomTeam")
	self:NetworkVar("Bool", 0, "RoomActive")
	self:NetworkVar("Bool", 1, "Enabled")
	-- CFuncRespawnRoomVisualizer::SetActive: solid, or a trigger that stops nobody.
	self:NetworkVar("Bool", 2, "FieldOn")
end

-- GMod caches ShouldCollide answers per pair until CollisionRulesChanged is
-- called, so the answer is computed from cached values that change only
-- together with that call (see the wetsand_visualizers Think hook below).
local visualizers = setmetatable({}, { __mode = "k" })

-- The team this forcefield stops the enemies of, or nobody.
function ENT:CollisionTeam()
	if not (self:GetEnabled() and self:GetFieldOn()) then return WETSAND.TEAM_UNASSIGNED end
	if WETSAND.State() == WETSAND.STATE.TEAM_WIN then return WETSAND.TEAM_UNASSIGNED end
	-- out of gameplay the spawn rooms are open to everyone
	if WETSAND.GameplayStopped() then return WETSAND.TEAM_UNASSIGNED end
	return self:GetRoomTeam()
end

function ENT:RefreshCollision()
	local team = self:CollisionTeam()
	if team == self.collisionTeam then return end
	self.collisionTeam = team
	self:CollisionRulesChanged()
end

function ENT:Blocks(ent)
	if not ent:IsPlayer() then return false end
	return WETSAND.TeamRules.VisualizerBlocks(self.collisionTeam, ent.wetsandCollisionTeam or ent:Team())
end

function ENT:InitCollision()
	self.collisionTeam = self:CollisionTeam()
	visualizers[self] = true
	self:SetCustomCollisionCheck(true)
end

hook.Add("ShouldCollide", "wetsand_respawn_room_visualizer", function(a, b)
	if visualizers[a] then return a:Blocks(b) end
	if visualizers[b] then return b:Blocks(a) end
end)

-- Both realms, every tick: pick up round-state changes (team win opens the
-- doors) and player team changes, and declare them to the physics engine.
hook.Add("Think", "wetsand_visualizers", function()
	for viz in pairs(visualizers) do
		if IsValid(viz) then viz:RefreshCollision() end
	end
	for _, ply in ipairs(player.GetAll()) do
		local team = ply:Team()
		if ply.wetsandCollisionTeam ~= team then
			ply.wetsandCollisionTeam = team
			ply:CollisionRulesChanged()
		end
	end
end)

if CLIENT then
	function ENT:Initialize()
		self:InitCollision()
	end

	function ENT:Draw()
		-- shown as in team win, to nobody's enemies, out of gameplay
		local teamWin = WETSAND.State() == WETSAND.STATE.TEAM_WIN or WETSAND.GameplayStopped()
		if self:GetEnabled() and WETSAND.TeamRules.VisualizerVisible(self:GetRoomTeam(), self:GetRoomActive(), teamWin, LocalPlayer():Team()) then
			self:DrawModel()
		end
	end
	ENT.DrawTranslucent = ENT.Draw
	return
end

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "model" then
		self.brushModel = value
	elseif k == "respawnroomname" then
		self.roomName = value
	elseif k == "solid_to_enemies" then
		self.solidToEnemies = value ~= "0"
	elseif k == "startdisabled" then
		self.startDisabled = value == "1"
	elseif k == "teamnum" then
		self.keyTeam = tonumber(value) or WETSAND.TEAM_UNASSIGNED
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	if self.brushModel then self:SetModel(self.brushModel) end
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BSP)
	if self.solidToEnemies == nil then self.solidToEnemies = true end
	self:SetEnabled(not self.startDisabled)
	self:SetRoomTeam(self.keyTeam or WETSAND.TEAM_UNASSIGNED)
	self:SetRoomActive(true)
	self:SetFieldOn(true)
	self:InitCollision()
end

-- Pushed by the room (CFuncRespawnRoom::SetActive / ChangeTeam).
function ENT:SetActive(active)
	self:SetFieldOn(active)
	self:SetRoomActive(active)
	self:RefreshCollision()
end

function ENT:ChangeTeam(team)
	self:SetRoomTeam(team)
	self:RefreshCollision()
end

-- CFuncRespawnRoomVisualizer::InputRoundActivate
function ENT:RoundActivate()
	local room = WETSAND.FindByName(self.roomName)
	if IsValid(room) and room:GetClass() == "func_respawnroom" then
		room:AddVisualizer(self)
		self:SetRoomTeam(room.team)
		self:SetRoomActive(room.active)
	end
	self:SetFieldOn(self.solidToEnemies)
	self:RefreshCollision()
end

local INPUTS = {
	enable = function(self) self:SetEnabled(true) end,
	disable = function(self) self:SetEnabled(false) end,
	setsolid = function(self, value)
		self.solidToEnemies = tostring(value) ~= "0" and tostring(value) ~= "false"
		self:SetFieldOn(self.solidToEnemies)
	end,
	roundactivate = function(self) self:RoundActivate() end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	self:RefreshCollision()
	return true
end
