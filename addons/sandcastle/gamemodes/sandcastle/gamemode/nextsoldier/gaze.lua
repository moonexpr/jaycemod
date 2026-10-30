-- Where a soldier's head looks, apart from where it aims: the player
-- model's head_yaw and head_pitch, over the aim_yaw and aim_pitch its gun
-- follows. The clients turn the head (base_nextsoldier's client Think); the
-- server only says where to look a while (a repath's new way).
--
-- Positions are { x, y, z }; angles are degrees, Source's: yaw to the left
-- positive, pitch below the eye positive.
-- Toward(eye, facing, target) -> the yaw of target from the way the body
--   aims (facing, its yaw) and its pitch, held to PITCH_LIMIT; nil when the
--   yaw is past YAW_LIMIT, which a head does not turn to
-- Goal{ fighting, eye, facing, hint, people } -> yaw, pitch the head turns to:
--   in a fight, along the aim; else the hint (a point, or nil) if the head
--   turns to it; else the nearest of people (points) within LOOK_RANGE it
--   turns to; else ahead
-- Step(seconds, urgent) -> how far the head turns in seconds: TURN_RATE's
--   worth, or, urgent (a fight begun, a hit), as far as it must: a snap
-- Approach(current, goal, step) -> current turned toward goal by at most step
-- Turn(current, goal, step, bodyTurned) -> the head's yaw: Approach, then
--   turned back by what the body turned since (left positive), so a
--   turning body does not drag the head past its goal, held to YAW_LIMIT
--   (C_HL2MP_Player::UpdateLookAt)
local atan2, deg, sqrt, huge, ipairs = math.atan2, math.deg, math.sqrt, math.huge, ipairs
module(...)

YAW_LIMIT, PITCH_LIMIT = 75, 45
-- People within LOOK_RANGE are looked at as they pass; a hint holds the
-- head HINT_SECONDS; the head turns TURN_RATE degrees a second, as an
-- HL2MP player's.
LOOK_RANGE, HINT_SECONDS, TURN_RATE = 300, 3, 130

local function Wrap(angle)
	return (angle + 180) % 360 - 180
end

function Toward(eye, facing, target)
	local dx, dy, dz = target.x - eye.x, target.y - eye.y, (target.z or 0) - (eye.z or 0)
	local yaw = Wrap(deg(atan2(dy, dx)) - facing)
	if yaw > YAW_LIMIT or yaw < -YAW_LIMIT then return nil end
	local pitch = -deg(atan2(dz, sqrt(dx * dx + dy * dy)))
	if pitch > PITCH_LIMIT then pitch = PITCH_LIMIT elseif pitch < -PITCH_LIMIT then pitch = -PITCH_LIMIT end
	return yaw, pitch
end

local function DistanceSquared(a, b)
	local dx, dy, dz = b.x - a.x, b.y - a.y, (b.z or 0) - (a.z or 0)
	return dx * dx + dy * dy + dz * dz
end

function Goal(view)
	if view.fighting then return 0, 0 end
	local eye, facing = view.eye, view.facing
	if view.hint then
		local yaw, pitch = Toward(eye, facing, view.hint)
		if yaw then return yaw, pitch end
	end
	local bestYaw, bestPitch, nearest = 0, 0, LOOK_RANGE * LOOK_RANGE
	for _, person in ipairs(view.people) do
		local d = DistanceSquared(eye, person)
		if d <= nearest then
			local yaw, pitch = Toward(eye, facing, person)
			if yaw then bestYaw, bestPitch, nearest = yaw, pitch, d end
		end
	end
	return bestYaw, bestPitch
end

function Step(seconds, urgent)
	if urgent then return huge end
	return TURN_RATE * seconds
end

function Approach(current, goal, step)
	if goal > current then
		current = current + step
		return current > goal and goal or current
	end
	current = current - step
	return current < goal and goal or current
end

function Turn(current, goal, step, bodyTurned)
	local yaw = Approach(current, goal, step) - bodyTurned
	if yaw > YAW_LIMIT then return YAW_LIMIT end
	if yaw < -YAW_LIMIT then return -YAW_LIMIT end
	return yaw
end
