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
-- The nav area its owner stands on is the nearest within this (a curved
-- pipe's area can lie further below than a step).
local SETTLE_REACH = 64
-- How much farther than the nearest (squared) an area still counts as under its owner.
local SEAM_SQR = 1

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

-- Whether it knows where its owner stands: its last known nav area (where
-- Path:Compute starts) is as near its owner as the nearest area is, or the owner is
-- near none. It follows its owner on its next think and the engine catches its area
-- up after that, so a tick or two after the owner is set down elsewhere. As near, not
-- the same: on the seam between two areas the engine keeps the one it was on and the
-- search may name the other, for as long as the owner stands there.
function ENT:Settled()
	local pos = self:GetOwner():GetPos()
	local here = navmesh.GetNearestNavArea(pos, false, SETTLE_REACH)
	if not IsValid(here) then return true end
	local last = self:GetLastKnownArea()
	if last == here then return true end
	if not IsValid(last) then return false end
	return last:GetClosestPointOnArea(pos):DistToSqr(pos) <= here:GetClosestPointOnArea(pos):DistToSqr(pos) + SEAM_SQR
end

-- The waypoints (Vectors) of a route from where it stands to goal, priced
-- by cost (Path:Compute's generator: area, fromArea, ladder, elevator,
-- length -> cost, or -1 where it may not go), or nil when there is none.
function ENT:PlanRoute(goal, cost)
	local owner = self:GetOwner()
	local watch = IsValid(owner) and owner.NSDebugPathWatch
	local Debug = watch and WS.require("features.nbdebug.model") or nil
	local recorder = Debug and watch.costs and cost and Debug.NewCostRecorder() or nil
	if recorder then
		local routeCost = cost
		cost = function(area, fromArea, ladder, elevator, length)
			local price = routeCost(area, fromArea, ladder, elevator, length)
			recorder:Record(area:GetID(), IsValid(fromArea) and fromArea:GetID() or nil, price)
			return price
		end
	end

	local path = Path("Follow")
	local began = Debug and SysTime()
	local found = path:Compute(self, goal, cost)
	local points, reportPoints, areaIds, lastArea = {}, {}, {}, nil
	for i, segment in ipairs(path:GetAllSegments() or {}) do
		points[i] = segment.pos
		if Debug then
			reportPoints[i] = {
				pos = segment.pos,
				move = Debug.MoveOfSegment(segment.type),
			}
			if IsValid(segment.area) then
				lastArea = segment.area
				areaIds[#areaIds + 1] = lastArea:GetID()
			end
		end
	end
	if Debug then
		hook.Run("WSNpcPathComputed", owner, Debug.NewPathReport({
			source = Debug.SOURCE_ENGINE,
			strategy = "AI War player:RouteCost",
			start = owner:GetPos(),
			goal = goal,
			found = found,
			points = reportPoints,
			areaIds = areaIds,
			totalCost = lastArea and lastArea:GetCostSoFar() or nil,
			microseconds = (SysTime() - began) * 1e6,
			nodesExpanded = recorder and recorder:Expanded() or nil,
			explored = recorder and recorder:Explored() or nil,
			computedAt = CurTime(),
		}))
	end
	return path:IsValid() and points or nil, found
end
