-- A bot player's navigator (features/aiwar/sv_bot_soldier.lua): a hidden
-- NextBot that plans the bot's routes with the engine's path search, which
-- needs a NextBot (Path:Compute starts from its last known nav area), as
-- GLambda Players' glace_navigator does. It stands where its owner stands,
-- touches nothing, is never seen, hurt (a blast reaches it all the same)
-- or anyone's target; it goes when its owner does.
ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "Bot Navigator"
ENT.Spawnable = false

-- Any model gives it a NextBot's hull; it is never drawn.
local MODEL = "models/player/police.mdl"
-- The nav area it stands over is looked for this far below it (two steps).
local SETTLE_REACH = 36

if SERVER then AddCSLuaFile() end

function ENT:Initialize()
	if CLIENT then return end
	self:SetModel(MODEL)
	self:SetSolid(SOLID_NONE)
	self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
	self:SetNoDraw(true)
	self:DrawShadow(false)
	self:AddFlags(FL_NOTARGET)
end

if SERVER then
	hook.Add("EntityTakeDamage", "ws_bot_navigator", function(ent)
		if ent:GetClass() == "ws_bot_navigator" then return true end
	end)
end

function ENT:RunBehaviour()
	while true do coroutine.yield() end
end

function ENT:Think()
	if CLIENT then return end
	local owner = self:GetOwner()
	if not IsValid(owner) then
		self:Remove()
		return
	end
	self:SetPos(owner:GetPos())
	self:NextThink(CurTime())
	return true
end

-- Whether it knows where it stands: its last known nav area (where
-- Path:Compute starts) is the one it stands over, or it stands over none.
-- The engine catches it up a tick or so after it is set down elsewhere.
function ENT:Settled()
	local here = navmesh.GetNavArea(self:GetPos(), SETTLE_REACH)
	return not IsValid(here) or self:GetLastKnownArea() == here
end

-- The waypoints (Vectors) of a route from where it stands to goal, priced
-- by cost (Path:Compute's generator: area, fromArea, ladder, elevator,
-- length -> cost, or -1 where it may not go), or nil when there is none.
function ENT:PlanRoute(goal, cost)
	local path = Path("Follow")
	path:Compute(self, goal, cost)
	if not path:IsValid() then return nil end
	local points = {}
	for i, segment in ipairs(path:GetAllSegments()) do points[i] = segment.pos end
	return points
end
