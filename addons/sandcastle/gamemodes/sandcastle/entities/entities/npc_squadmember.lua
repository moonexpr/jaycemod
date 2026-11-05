-- npc_squadmember: a probe of the legs alone. An npc_pathfollower whose only tree is
-- GroupIdentityBehavior, it never moves: where an order would put it is shown as a cross
-- (the Local Behavior Tool), its path there as a path follower's, and its spacing beside it.
--
-- member:NSLegsGive(order, place) tells it an order and its place in it; nil dissolves it.
AddCSLuaFile()

ENT.Base = "npc_pathfollower"
ENT.Type = "nextbot"
ENT.PrintName = "Squad Member"
ENT.Category = "Sandcastle"
ENT.Spawnable = false

local BaseClass = baseclass.Get("npc_pathfollower")

if CLIENT then
	local ORDER_COLORS = { Muster = Color(120, 255, 120), FallBack = Color(255, 170, 60) }
	local CANNOT_STAND_COLOR = Color(255, 70, 70)
	local SELECTED_COLOR = Color(90, 220, 255)
	local RING_COLOR, CROWDED_COLOR = Color(160, 160, 160), Color(255, 90, 210)
	local CROSS_SIZE, SELECTED_RADIUS, FEET = 16, 22, Vector(0, 0, 3)
	local RING_STEPS = 32

	local function Cross(at, color)
		render.DrawLine(at - Vector(CROSS_SIZE, 0, 0), at + Vector(CROSS_SIZE, 0, 0), color)
		render.DrawLine(at - Vector(0, CROSS_SIZE, 0), at + Vector(0, CROSS_SIZE, 0), color)
		render.DrawLine(at, at + Vector(0, 0, CROSS_SIZE * 2), color)
	end

	local function Ring(center, radius, color)
		local last = center + Vector(radius, 0, 0)
		for i = 1, RING_STEPS do
			local angle = i / RING_STEPS * 2 * math.pi
			local point = center + Vector(math.cos(angle) * radius, math.sin(angle) * radius, 0)
			render.DrawLine(last, point, color)
			last = point
		end
	end

	-- Drawn apart from the model, so a place shows with its member out of view.
	hook.Add("PostDrawTranslucentRenderables", "npc_squadmember", function(_, sky)
		if sky then return end
		local showSpacing = GetConVar("ns_localbehavior_spacing")
		for _, member in ipairs(ents.FindByClass("npc_squadmember")) do
			local feet = member:GetPos() + FEET
			local kind = member:GetNW2String("NSLegsOrder", "")
			if kind ~= "" then
				local place = member:GetNW2Vector("NSLegsPlace", vector_origin)
				local color = member:GetNW2Bool("NSLegsStands", false) and ORDER_COLORS[kind] or CANNOT_STAND_COLOR
				Cross(place, color)
			end
			if member:GetNW2Bool("NSSquadSelected", false) then Ring(feet, SELECTED_RADIUS, SELECTED_COLOR) end
			if showSpacing and showSpacing:GetBool() then
				local spacing = member:GetNW2Float("NSLegsSpacing", 0)
				local push = member:GetNW2Vector("NSLegsPush", vector_origin)
				local crowded = push:LengthSqr() > 0
				Ring(feet, spacing, crowded and CROWDED_COLOR or RING_COLOR)
				if crowded then render.DrawLine(feet, feet + push * spacing, CROWDED_COLOR) end
			end
		end
	end)
	return
end

-- A place is looked for from this far above it to this far below, a body's own hull fitting.
local SEARCH_ABOVE, SEARCH_BELOW = 64, 256
local LIFT = Vector(0, 0, 1)
-- Its way to a place is swept a stair's step above the floor, so a step does not wall it off.
local STEP = 18
local GroupIdentity = nextsoldier.behavior.group_identity

-- A probe is not hurt: a stray shot would take it off the bench.
hook.Add("EntityTakeDamage", "npc_squadmember", function(ent)
	if ent:GetClass() == "npc_squadmember" then return true end
end)

function ENT:CustomInitialize()
	self.NSToolManaged = true
	BaseClass.CustomInitialize(self)
end

function ENT:NSInitialAction()
	return GroupIdentity.InitialAction(nextsoldier.engine, GroupIdentity.LegsAtEase:New())
end

function ENT:NSLegsOrder() return self.nsLegsOrder end

-- The ground under a slot where its body fits there, or nil: the map's, not who stands there now.
local function Ground(self, slot)
	local at = Vector(slot.x, slot.y, slot.z)
	local floor = util.TraceLine({
		start = at + Vector(0, 0, SEARCH_ABOVE),
		endpos = at - Vector(0, 0, SEARCH_BELOW),
		mask = MASK_NPCSOLID_BRUSHONLY,
	})
	if not floor.Hit or floor.StartSolid then return nil end
	local mins, maxs = self:GetCollisionBounds()
	local fit = util.TraceHull({
		start = floor.HitPos + LIFT,
		endpos = floor.HitPos + LIFT,
		mins = mins,
		maxs = maxs,
		mask = MASK_NPCSOLID_BRUSHONLY,
	})
	if fit.Hit then return nil end
	return floor.HitPos
end

-- What an order around point may give a body of its size: admit(slot) -> the ground it would
-- stand on, where it fits and no wall stands between it and point; nil elsewhere.
function ENT:NSLegsAdmit(point)
	local mins, maxs = self:GetCollisionBounds()
	local from = Ground(self, point)
	local sweepMins, sweepMaxs = Vector(mins.x, mins.y, 0), Vector(maxs.x, maxs.y, maxs.z - STEP)
	return function(slot)
		local ground = from and Ground(self, slot)
		if not ground then return nil end
		local reach = util.TraceHull({
			start = from + Vector(0, 0, STEP),
			endpos = ground + Vector(0, 0, STEP),
			mins = sweepMins,
			maxs = sweepMaxs,
			mask = MASK_NPCSOLID_BRUSHONLY,
		})
		if reach.Hit then return nil end
		return { x = ground.x, y = ground.y, z = ground.z }
	end
end

-- Its order and its place in it: nil, it has no room near; no order dissolves it.
function ENT:NSLegsGive(order, place)
	self.nsLegsOrder = order
	self:SetNW2String("NSLegsOrder", order and order.kind or "")
	if not order then return end
	self.nsLegsPlace = place and Vector(place.x, place.y, place.z)
	self:SetNW2Bool("NSLegsStands", place ~= nil)
	self:SetNW2Vector("NSLegsPlace", self.nsLegsPlace or self:GetPos())
end

-- Its way to its place, planned and shown as a path follower's, walked by none: it stands.
function ENT:NSLegsHeadForPlace()
	local place = self.nsLegsPlace
	if not place then return end
	self:PlanPath(place)
	self:NSSyncDebug()
end

-- What its team's spacing would do to it where it stands, as a soldier's tree works it out.
function ENT:NSLegsSense()
	local engine = nextsoldier.engine
	local pos = self:GetPos()
	local others = {}
	for _, other in ipairs(ents.FindByClass("npc_squadmember")) do
		if other ~= self and other:GetNW2Int("ws_team", TEAM_UNASSIGNED) == self:GetNW2Int("ws_team", TEAM_UNASSIGNED) then
			local at = other:GetPos()
			others[#others + 1] = { x = at.x, y = at.y, z = at.z }
		end
	end
	local x, y = engine.Separation({ x = pos.x, y = pos.y, z = pos.z }, others, self:EntIndex())
	self:SetNW2Float("NSLegsSpacing", engine.GroupSpacing())
	self:SetNW2Vector("NSLegsPush", Vector(x, y, 0))
end
