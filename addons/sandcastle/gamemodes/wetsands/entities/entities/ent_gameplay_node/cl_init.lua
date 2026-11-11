include ("shared.lua")

-- GMod clears the global once the file has run.
local ENT = ENT

local Model = WS.require ("features.builder.model")

local PLATE = "models/props_gameplay/cap_point_base.mdl"
local BOUNDS_MINS, BOUNDS_MAXS = Vector (-64, -64, 0), Vector (64, 64, 200)

local function RailAngle (dir, alongY)
	local ang = dir:Angle ()
	if alongY then ang:RotateAroundAxis (ang:Up (), -90) end
	return ang
end

-- The rails to the next node, in building and in a game alike; while building
-- the tail, the goal, shows its plate and hologram, as a game's point will.
function ENT:Draw ()
	self:DrawModel ()
	local nextNode = self:GetNextNode ()
	if IsValid (nextNode) then
		local from, to = self:GetPos (), nextNode:GetPos ()
		local dir = (to - from):GetNormalized ()
		for _, rail in ipairs (ENT.TrackSegments (from, to)) do
			render.Model ({ model = rail.model, pos = rail.pos, angle = RailAngle (dir, rail.alongY) })
		end
	elseif not WS.Active () or WS.GameplayStopped () then
		render.Model ({ model = PLATE, pos = self:GetPos (), angle = angle_zero })
		self:DrawHologram ()
	end
end

-- Drawn as far as its rails reach, not its model.
function ENT:UpdateRenderBounds ()
	local nextNode = self:GetNextNode ()
	local far = IsValid (nextNode) and nextNode:GetPos () or self:GetPos ()
	self:SetRenderBoundsWS (self:GetPos () + BOUNDS_MINS, far + BOUNDS_MAXS)
end
