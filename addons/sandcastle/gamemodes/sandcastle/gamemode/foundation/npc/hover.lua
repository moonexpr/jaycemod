-- Hover locomotion for a flying NPC (CEyeballBossLocomotion, as a model).
-- New(cfg, vector): cfg = { hoverHeight, acceleration, horizontalDamping,
-- verticalDamping }, and vector(x, y, z) builds the engine's vectors.
--
-- Each tick the binding calls Approach(goal, origin) as often as the
-- Behavior asks, then Step(dt, origin, groundZ, alive), which returns the
-- new velocity and the move to try. The binding resolves that move with
-- hull traces and, when it hit anything, calls Bounce(normal) with the
-- normalised sum of the surface normals. `groundZ` is the height of the
-- ground below: the binding traces up to the ceiling, then down from there.
-- (MaintainAltitude also looks 50 units ahead while IsAttemptingToMove, but
-- CEyeballBossLocomotion::Approach never starts that timer, so it looks
-- straight down.)
local max, min, sqrt, setmetatable = math.max, math.min, math.sqrt, setmetatable
module(...)

FALL_ACCELERATION = 300 -- MaintainAltitude once dead

local Hover = {}
Hover.__index = Hover

function New(cfg, vector)
	return setmetatable({
		cfg = cfg,
		vector = vector,
		desiredAltitude = cfg.hoverHeight,
		vx = 0,
		vy = 0,
		vz = 0,
		ax = 0,
		ay = 0,
		az = 0,
	}, Hover)
end

function Hover:SetDesiredAltitude(height) self.desiredAltitude = height end
function Hover:GetDesiredAltitude() return self.desiredAltitude end
function Hover:GetVelocity() return self.vector(self.vx, self.vy, self.vz) end
function Hover:GetGroundSpeed() return sqrt(self.vx * self.vx + self.vy * self.vy) end

-- CEyeballBossLocomotion::Approach: level, full acceleration towards the goal.
function Hover:Approach(goal, origin)
	local dx, dy = goal.x - origin.x, goal.y - origin.y
	local length = sqrt(dx * dx + dy * dy)
	if length == 0 then return end
	local a = self.cfg.acceleration
	self.ax = self.ax + a * dx / length
	self.ay = self.ay + a * dy / length
end

-- CEyeballBossLocomotion::MaintainAltitude
function Hover:MaintainAltitude(origin, groundZ, alive)
	if not alive then
		self.ax, self.ay, self.az = 0, 0, -FALL_ACCELERATION
		return
	end
	local a = self.cfg.acceleration
	local err = self.desiredAltitude - (origin.z - groundZ)
	self.az = self.az + max(-a, min(a, err))
end

-- CEyeballBossLocomotion::Update, up to the collision checks.
function Hover:Step(dt, origin, groundZ, alive)
	self:MaintainAltitude(origin, groundZ, alive)
	local h, v = self.cfg.horizontalDamping, self.cfg.verticalDamping
	self.vx = self.vx + (self.ax - self.vx * h) * dt
	self.vy = self.vy + (self.ay - self.vy * h) * dt
	self.vz = self.vz + (self.az - self.vz * v) * dt
	self.ax, self.ay, self.az = 0, 0, 0
	return self:GetVelocity(), self.vector(self.vx * dt, self.vy * dt, self.vz * dt)
end

-- Reflect off a surface.
function Hover:Bounce(normal)
	local d = 2 * (self.vx * normal.x + self.vy * normal.y + self.vz * normal.z)
	self.vx = self.vx - d * normal.x
	self.vy = self.vy - d * normal.y
	self.vz = self.vz - d * normal.z
end
