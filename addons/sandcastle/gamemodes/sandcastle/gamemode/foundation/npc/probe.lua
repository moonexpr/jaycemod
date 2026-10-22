-- A path follower stripped of the war: a probe walks a list of points in
-- order (a lane's, features/aiwar/sv_probe.lua's ns_lanes_probe), moved as
-- a soldier is, and says where it stalls. Stalled (no PROGRESS for
-- STUCK_TIME), it tries the soldier's remedies in turn, a fresh path, then
-- a hop toward the point, each found; still stalled, the point is found
-- STUCK and it goes on to the next. A leg that keeps moving but takes
-- LEG_TIME is found SLOW and skipped the same way. Off the nav mesh for
-- OFF_MESH_TIME (fallen into a hole, onto a roof, into a plate), it is
-- found OFFMESH and put back where it last stood on the mesh, as the war's
-- observer puts back a soldier.
--
-- Step(pos, now, onMesh) is told where the probe stands and whether a nav
-- area is under it (false: none), and answers with what to do:
-- { kind = MOVE, to }, { kind = REPATH }, { kind = HOP, to },
-- { kind = RECOVER, to } or { kind = DONE }.
local Geometry = require("foundation.math.geometry")
local abs = math.abs
local setmetatable = setmetatable
module(...)

ARRIVE = 48 -- across the ground
HEIGHT = 36 -- up or down: a stair's or a slope's difference from the lane's point
PROGRESS = 24
STUCK_TIME = 3
LEG_TIME = 30
OFF_MESH_TIME = 5

MOVE, REPATH, HOP, RECOVER, DONE = "move", "repath", "hop", "recover", "done"
STUCK, SLOW, OFFMESH = "stuck", "slow", "offmesh"

-- The remedies, in the order a stall gets them.
local REMEDIES = { REPATH, HOP }

local Probe = {}
Probe.__index = Probe

function New(points, now)
	return setmetatable({
		points = points,
		index = 1,
		reached = 0,
		findings = {},
		legStart = now,
	}, Probe)
end

local Across = Geometry.Distance2D

function Probe:Find(kind, at)
	self.findings[#self.findings + 1] = { kind = kind, index = self.index, point = self.points[self.index], at = at }
end

-- On to the next point, from pos at now.
function Probe:Next(pos, now)
	self.index = self.index + 1
	self.legStart = now
	self.anchor, self.anchorAt, self.stage = pos, now, 0
end

function Probe:Step(pos, now, onMesh)
	if onMesh == false then
		self.offSince = self.offSince or now
		if self.lastOnMesh and now - self.offSince >= OFF_MESH_TIME then
			self:Find(OFFMESH, pos)
			self.offSince = nil
			self.anchor, self.anchorAt, self.stage = self.lastOnMesh, now, 0
			return { kind = RECOVER, to = self.lastOnMesh }
		end
	else
		self.offSince, self.lastOnMesh = nil, pos
	end
	local point = self.points[self.index]
	while point and Across(pos, point) <= ARRIVE and abs(pos.z - point.z) <= HEIGHT do
		self.reached = self.reached + 1
		self:Next(pos, now)
		point = self.points[self.index]
	end
	if not point then return { kind = DONE } end
	if not self.anchor or Across(pos, self.anchor) > PROGRESS then
		self.anchor, self.anchorAt, self.stage = pos, now, 0
	end
	if now - self.legStart >= LEG_TIME then
		self:Find(SLOW, pos)
		self:Next(pos, now)
		return self:Step(pos, now)
	end
	if now - self.anchorAt > STUCK_TIME then
		self.stage = self.stage + 1
		self.anchorAt = now
		local remedy = REMEDIES[self.stage]
		if remedy then
			self:Find(remedy, pos)
			return { kind = remedy, to = point }
		end
		self:Find(STUCK, pos)
		self:Next(pos, now)
		return self:Step(pos, now)
	end
	return { kind = MOVE, to = point }
end

-- How many points it reached.
function Probe:Reached()
	return self.reached
end

-- What it found, in order: { kind (REPATH, HOP, STUCK, SLOW, OFFMESH), index, point, at }.
function Probe:Findings()
	return self.findings
end
