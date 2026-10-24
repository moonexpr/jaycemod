-- A soldier in a player's body (the AI war's bot soldiers), driven as TF2's
-- bots drive theirs (PlayerBody, PlayerLocomotion): each tick, where it is
-- sent, where it looks and what it shoots become the command a player's
-- keys would make. Its moves and its aim are apart, as a player's are: it
-- walks one way (the command's move angles) and looks another (its eyes),
-- turning no faster than TURN_RATE.
--
-- Angles are Source's, in degrees: yaw 0 along +x, 90 along +y; pitch
-- positive looking down.
local abs, atan2, deg, sqrt = math.abs, math.atan2, math.deg, math.sqrt
local setmetatable = setmetatable
module(...)

-- How fast it turns its eyes, degrees a second (CTFBot's head turning,
-- about a human's flick).
TURN_RATE = 720
-- How near its target it stops.
ARRIVE = 16
-- Trying to move, slower than STUCK_SPEED for STUCK_TIME seconds on the
-- ground: stuck, it jumps, ducking in the air for CROUCH_JUMP_TIME (a
-- crouch jump clears what a plain one does not).
STUCK_SPEED, STUCK_TIME = 30, 0.8
CROUCH_JUMP_TIME = 0.5
-- A gun fires once its aim is within the enemy's width at its distance, or
-- FIRE_CONE degrees of its centre, whichever is wider; a melee weapon
-- strikes within MELEE_CONE degrees.
FIRE_CONE, MELEE_CONE = 2, 30
-- A door ahead is used once, and again only after USE_INTERVAL seconds if
-- it still stands in the way (GLambda's players' door check).
USE_INTERVAL = 2

local Body = {}
Body.__index = Body

function New()
	return setmetatable({
		stuckSince = nil, -- when it began to make no headway, on the ground
		jumpedAt = nil, -- its last jump's time, for the crouch in the air
		jumped = false, -- it pressed jump last tick: the key is let go before another
		attacked = false, -- it pressed attack last tick
		usedAt = nil, -- when it last used a door
		inJumpArea = false,
	}, Body)
end

-- An angle in (-180, 180].
local function Normal(a)
	a = a % 360
	if a > 180 then a = a - 360 end
	return a
end

local function YawTo(from, to)
	return deg(atan2(to.y - from.y, to.x - from.x))
end

local function Distance2D(a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	return sqrt(dx * dx + dy * dy)
end

-- The eye angles toward p from the eye at eyePos.
local function AnglesTo(eyePos, p)
	local flat = Distance2D(eyePos, p)
	return -deg(atan2(p.z - eyePos.z, flat)), YawTo(eyePos, p)
end

-- One tick's turn from (pitch, yaw) toward (toPitch, toYaw): both axes
-- scaled together so the larger moves at most step.
local function Turn(pitch, yaw, toPitch, toYaw, step)
	local dp, dy = toPitch - pitch, Normal(toYaw - yaw)
	local largest = abs(dp) > abs(dy) and abs(dp) or abs(dy)
	if largest <= step then return toPitch, Normal(toYaw) end
	local scale = step / largest
	return pitch + dp * scale, Normal(yaw + dy * scale)
end

-- Whether a weapon at the eye's (pitch, yaw) would hit the enemy at aim,
-- radius wide (a melee weapon: and within its reach).
local function OnTarget(sense, pitch, yaw)
	local weapon = sense.weapon
	local toPitch, toYaw = AnglesTo(sense.eyePos, sense.aim)
	local off = abs(toPitch - pitch)
	local offYaw = abs(Normal(toYaw - yaw))
	if offYaw > off then off = offYaw end
	local distance = Distance2D(sense.eyePos, sense.aim)
	if weapon.melee then
		local dz = sense.aim.z - sense.eyePos.z
		return sqrt(distance * distance + dz * dz) <= weapon.reach and off <= MELEE_CONE
	end
	local cone = deg(atan2(sense.aimRadius or 0, distance))
	if cone < FIRE_CONE then cone = FIRE_CONE end
	return off <= cone
end

-- The jump key this tick: pressed for one tick, let go the next.
local function Jump(self, now, want)
	if want and not self.jumped then
		self.jumped = true
		self.jumpedAt = now
		self.stuckSince = nil
		return true
	end
	self.jumped = false
	return false
end

-- Sent nowhere, the way it moves for its enemy at aim, as an NPC's own AI
-- fights (DrGBase's chase and avoid ranges for the weapon held): toward it
-- past chase, away from it inside avoid, nowhere between; nil without
-- ranges or an enemy in sight.
local function Engage(sense)
	local aim, chase, avoid = sense.aim, sense.chase, sense.avoid
	if not (aim and chase) then return nil end
	local distance = Distance2D(sense.pos, aim)
	if distance > chase then return YawTo(sense.pos, aim) end
	if avoid and distance < avoid then return Normal(YawTo(sense.pos, aim) + 180) end
	return nil
end

-- The command for this tick. sense: { pos, eyePos, eye = { pitch, yaw },
-- speed (across the ground), onGround, target (where it is sent, or nil),
-- walk (at a walk), crouchArea, jumpArea (the nav mesh's where it stands),
-- hop (its orders ask a jump), lowBlocked, headBlocked (something ahead at
-- its knees, at its head), doorAhead, look (where to face, or nil), aim
-- (its enemy's centre while it is recognized and in sight, or nil),
-- aimRadius, chase, avoid (its weapon's ranges, or nil), fire (it may
-- shoot), weapon = { automatic, melee, reach, clip (-1: none), reserve } or
-- nil }. Returns { moveYaw (nil: stand), walk, duck, jump, use, attack,
-- reload, pitch, yaw }.
function Body:Command(now, dt, sense)
	local pos, target = sense.pos, sense.target
	local moveYaw = nil
	if target then
		if Distance2D(pos, target) > ARRIVE then moveYaw = YawTo(pos, target) end
	else
		moveYaw = Engage(sense)
	end

	-- stuck: counted only on the ground, trying to move
	if moveYaw and sense.onGround and sense.speed < STUCK_SPEED then
		self.stuckSince = self.stuckSince or now
	else
		self.stuckSince = nil
	end
	local stuck = self.stuckSince ~= nil and now - self.stuckSince >= STUCK_TIME
	local enteredJumpArea = sense.jumpArea and not self.inJumpArea
	self.inJumpArea = sense.jumpArea or false
	-- an obstacle at its knees with room above is jumped; one at its head
	-- with room below ducked under; a wall is neither
	local moving = moveYaw ~= nil
	local hurdle = moving and sense.lowBlocked and not sense.headBlocked or false
	local lintel = moving and sense.headBlocked and not sense.lowBlocked or false
	local wantJump = sense.onGround and (stuck or enteredJumpArea or sense.hop or hurdle or false)
	local jump = Jump(self, now, wantJump)
	local crouchJump = not sense.onGround and self.jumpedAt ~= nil and now - self.jumpedAt <= CROUCH_JUMP_TIME
	local use = moving and sense.doorAhead and (self.usedAt == nil or now - self.usedAt >= USE_INTERVAL) or false
	if use then self.usedAt = now end

	-- eyes: on the enemy, else where told, else the way it goes
	local eye = sense.eye
	local toPitch, toYaw = eye.pitch, eye.yaw
	if sense.aim then
		toPitch, toYaw = AnglesTo(sense.eyePos, sense.aim)
	elseif sense.look then
		toPitch, toYaw = AnglesTo(sense.eyePos, sense.look)
	elseif moveYaw then
		toPitch, toYaw = 0, moveYaw
	end
	local pitch, yaw = Turn(eye.pitch, eye.yaw, toPitch, toYaw, TURN_RATE * dt)

	local attack, reload = false, false
	local weapon = sense.weapon
	if weapon then
		local loaded = weapon.melee or weapon.clip ~= 0
		if not loaded then
			reload = weapon.reserve > 0
		elseif sense.aim and sense.fire and OnTarget(sense, pitch, yaw) then
			attack = weapon.automatic or not self.attacked
		end
	end
	self.attacked = attack

	return {
		moveYaw = moveYaw,
		walk = sense.walk and moveYaw ~= nil or false,
		duck = sense.crouchArea or crouchJump or lintel or false,
		jump = jump,
		use = use,
		attack = attack,
		reload = reload,
		pitch = pitch,
		yaw = yaw,
	}
end
