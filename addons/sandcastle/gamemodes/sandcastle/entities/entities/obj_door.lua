-- obj_door: an access door a support unit sets in a room's doorway. It lets its own team through
-- (gameplay.buildings' Passes) and stops every other, who must shoot it down; it shows itself open
-- while a teammate is within DOOR_OPEN_REACH, and shut DOOR_CLOSE_DELAY after the last has gone. Its
-- collision is answered as func_respawnroomvisualizer's: ShouldCollide, per pair, by team. While it
-- stands, the nav areas within AREA_REACH of it are closed to every other team: ClosedTo(areaId,
-- team), which a path's cost reads, over the one record of all doors (an entity's copy of its
-- class table copies a table on it, never a function's upvalue, so the record is the file's).
AddCSLuaFile()

ENT.Base = "base_obj"
ENT.Kind = "door"
ENT.Model = "models/props_lab/blastdoor001c.mdl"
ENT.PrintName = "Access Door"

local Buildings = gameplay.buildings

local OPEN_ALPHA, BUILD_ALPHA = 0.3, 0.25
-- The nav areas a door closes: within AREA_REACH across, AREA_STEP up or down.
local AREA_REACH, AREA_STEP = 48, 64

local barriers = Buildings.Barriers()

function ENT.ClosedTo(areaId, team) return barriers:Blocks(areaId, team) end

local doors = setmetatable({}, { __mode = "k" })

function ENT:ObjDataTables()
	self:NetworkVar("Bool", 0, "Open")
end

function ENT:Blocks(ent)
	if not (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) then return true end
	return not Buildings.Passes(self:GetObjTeam(), WS.TeamNumber(ent))
end

hook.Add("ShouldCollide", "ws_obj_door", function(a, b)
	if doors[a] then return a:Blocks(b) end
	if doors[b] then return b:Blocks(a) end
end)

function ENT:Initialize()
	if SERVER then
		self.BaseClass.Initialize(self)
		local areas = {}
		for _, area in ipairs(navmesh.Find(self:WorldSpaceCenter(), AREA_REACH, AREA_STEP, AREA_STEP)) do
			areas[#areas + 1] = area:GetID()
		end
		barriers:Add(self, self:GetObjTeam(), areas)
	end
	doors[self] = true
	self:SetCustomCollisionCheck(true)
end

function ENT:OnRemove()
	barriers:Remove(self)
end

if SERVER then
	-- Set in a doorway, it may reach into the walls either side: it fits where no body stands in it.
	function ENT:Fits()
		local builder = self:GetBuilder()
		for _, ent in ipairs(ents.FindInBox(self:WorldSpaceAABB())) do
			if ent ~= self and ent ~= builder and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) then return false end
		end
		return true
	end

	function ENT:ObjThink()
		local now, team = CurTime(), self:GetObjTeam()
		for _, ent in ipairs(ents.FindInSphere(self:WorldSpaceCenter(), Buildings.DOOR_OPEN_REACH)) do
			if (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and Buildings.Passes(team, WS.TeamNumber(ent)) then
				self.lastNear = now
				break
			end
		end
		self:SetOpen(self.lastNear ~= nil and now - self.lastNear < Buildings.DOOR_CLOSE_DELAY)
	end
end

-- Its model has no build animation: half seen going up, growing whole, then see-through while open.
function ENT:Draw()
	local share = self:Constructed()
	render.SetBlend(share < 1 and BUILD_ALPHA + (1 - BUILD_ALPHA) * share or self:GetOpen() and OPEN_ALPHA or 1)
	self:DrawModel()
	render.SetBlend(1)
end
