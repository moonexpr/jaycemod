-- nextsoldier.locomotion.flight: HL2's physics flyer (CAI_BasePhysicsFlyingBot,
-- ai_basenpc_physicsflyer.h/.cpp, and CNPC_BaseScanner's MoveToTarget and MoveExecute_Alive in
-- npc_basescanner.cpp) as plain functions over { x, y, z } points: the velocity it wants each think,
-- and the force its motion controller pushes its physics object by toward it.
local T = dofile ("tests/harness.lua")
local Flight = nextsoldier.locomotion.flight

local function V (x, y, z) return { x = x, y = y, z = z } end
local function Near (actual, expected, what)
	T.near (actual.x, expected.x, 1e-4, what .. ": x")
	T.near (actual.y, expected.y, 1e-4, what .. ": y")
	T.near (actual.z, expected.z, 1e-4, what .. ": z")
end

T.test ("its values are HL2's", function ()
	T.eq (Flight.ACCEL_AHEAD,  250,  "myAccel, the target in front")
	T.eq (Flight.ACCEL_BEHIND, 128,  "myAccel, flying away from it")
	T.eq (Flight.ACCEL_Z,      400,  "myZAccel")
	T.eq (Flight.DECAY,        0.15, "myDecay")
	T.eq (Flight.AHEAD_DOT, 0.25)
	T.eq (Flight.NOISE_SCALE, 3, "MoveExecute_Alive's noiseScale")
	T.eq (Flight.BANK_ROLL, 120)
	T.eq (Flight.FORCE_LIMIT, 3000, "ClampMotorForces")
	T.eq (Flight.WEIGHTLESS,  800,  "ClampMotorForces' weightlessness")
	T.eq (Flight.BOUNCE,      0.5,  "VelocityToAvoidObstacles")
	T.eq (Flight.LIFT,       50)
	T.eq (Flight.LIFT_FLOOR, 0.1)
	T.eq (Flight.THINK_INTERVAL, 0.1, "CAI_BaseNPC::NPCThink's next think at normal efficiency")
end)

T.test ("ExponentialDecay is mathlib's", function ()
	T.near (Flight.ExponentialDecay (0.15, 1, 1),   0.15,             1e-9)
	T.near (Flight.ExponentialDecay (0.15, 1, 0.5), math.sqrt (0.15), 1e-9)
	T.near (Flight.ExponentialDecay (0.15, 1, 0),   1,                1e-9)
end)

T.test ("steering: decays what it had and accelerates toward its target, harder ahead of it", function ()
	-- at rest, the target 1000 along x: no current direction, so the slower acceleration
	local v = Flight.Steer (V (0, 0, 0), V (0, 0, 0), V (1000, 0, 0), 0.1)
	Near (v, V (128 * 0.1, 0, 0), "from rest")
	-- moving toward it: 250
	local decay = Flight.ExponentialDecay (0.15, 1, 0.1)
	v = Flight.Steer (V (100, 0, 0), V (0, 0, 0), V (1000, 0, 0), 0.1)
	Near (v, V (decay * 100 + 250 * 0.1, 0, 0), "ahead")
	-- straight up: z takes myZAccel
	v = Flight.Steer (V (0, 0, 10), V (0, 0, 0), V (0, 0, 1000), 0.1)
	Near (v, V (0, 0, decay * 10 + 400 * 0.1), "up")
end)

T.test ("steering: no harder than would carry it past its target this think", function ()
	local v = Flight.Steer (V (0, 0, 1), V (0, 0, 0), V (0, 0, 2), 0.1)
	local decay = Flight.ExponentialDecay (0.15, 1, 0.1)
	-- 2 units off over 0.1 s: at most 20 an axis
	Near (v, V (0, 0, decay * 1 + 20 * 0.1), "capped")
end)

T.test ("steering at its target only decays", function ()
	local decay = Flight.ExponentialDecay (0.15, 1, 0.1)
	Near (Flight.Steer (V (10, 0, 0), V (5, 5, 5), V (5, 5, 5), 0.1), V (decay * 10, 0, 0), "there")
end)

T.test ("noise: each axis its own, time-coherent; an axis with no modulation none", function ()
	local mod, t = V (2, -1, 3), 1.5
	local v = Flight.Noise (V (0, 0, 0), mod, t, 3)
	Near (v, V (3 * math.sin (2 * t + 2), 3 * math.cos (-1 * t - 1), -3 * math.cos (3 * t + 3)), "noise")
	Near (Flight.Noise (V (1, 1, 1), V (0, 0, 0), t, 3), V (1, 1, 1), "none")
end)

T.test ("its bob: x and y within 2, z between 2 and 4 either way, by the caller's draws", function ()
	local draws = { 0, 1, 0.5, 0.9 }
	local i = 0
	local function draw () i = i + 1 return draws [i] end
	Near (Flight.NoiseMod (draw), V (-2, 2, 3), "first")
	draws, i = { 0.5, 0.5, 0, 0.1 }, 0
	Near (Flight.NoiseMod (draw), V (0, 0, -2), "z turned down on a low last draw")
end)

T.test ("avoiding: a wall ahead bounces it off at half its speed; the ground near lifts it", function ()
	Near (Flight.Avoid (V (100, 0, 0), V (-1, 0, 0), nil), V (-50, 0, 0), "off the wall")
	Near (Flight.Avoid (V (0, 0, 0), nil, 0.5),            V (0, 0, 100), "half way to its least height")
	Near (Flight.Avoid (V (0, 0, 0), nil, 0),              V (0, 0, 500), "no nearer than LIFT_FLOOR")
	Near (Flight.Avoid (V (0, 0, 0), nil, nil),            V (0, 0, 0),   "nothing near")
	Near (Flight.Avoid (V (100, 0, 0), V (-1, 0, 0), 0.5), V (-50, 0, 0), "a wall comes first")
end)

T.test ("its speed held, and its fall", function ()
	Near (Flight.Limit (V (300, 400, 0), 250, -1), V (150, 200, 0), "held to 250")
	Near (Flight.Limit (V (0, 0, -200), 250, 100), V (0, 0, -100),  "its fall held")
	Near (Flight.Limit (V (0, 0, -200), 250, -1),  V (0, 0, -200),  "no fall limit")
end)

T.test ("as MoveExecute_Alive calls it: the scanner's speed held to its own, the 'max speed' only its fall", function ()
	local enemy = Flight.Limits (250, true)
	T.eq (enemy.speed, 250, "m_flSpeed")
	T.eq (enemy.fall,  500, "GetMaxSpeed () * 2, passed as zLimit")
	local calm = Flight.Limits (250, false)
	T.eq (calm.speed, 250)
	T.eq (calm.fall,  250)
end)

T.test ("banking: rolled toward the way it turns, by how fast it goes", function ()
	local dir, right = V (0, 1, 0), V (0, 1, 0)
	local bank = Flight.Banking (dir, right, 250, 250)
	Near (bank,                                V (0, 0, 120), "full speed, turning wholly right")
	Near (Flight.Banking (dir, right, 0, 250), V (0, 0, 0),   "at rest")
	local half = 3 * 0.25 - 2 * 0.125
	Near (Flight.Banking (V (1, 0, 0), right, 125, 250), V (half, 0, 0), "half speed: SimpleSpline")
end)

T.test ("its motion controller: the velocity it wants against what it has, clamped, weightless", function ()
	local linear, angular = Flight.Thrust (
		{
			want = V (100, -10000, 0),
			velocity = V (0, 0, 0),
			angles = { p = 0, y = 0, r = 0 },
			angularVelocity = V (0, 0, 0),
			banking = V (0, 0, 0),
			headYaw = 90
		}, 0.1)
	Near (linear,  V (1000, -3000, 800), "(want - actual) / dt, clamped to 3000, and 800 up")
	Near (angular, V (0, 0, 900),        "turned toward its head's yaw")
	local _, rolled = Flight.Thrust (
		{
			want = V (0, 0, 0),
			velocity = V (0, 0, 0),
			angles = { p = 0, y = 0, r = 350 },
			angularVelocity = V (0, 0, 0),
			banking = V (0, 0, 20),
			headYaw = 0
		}, 0.1)
	Near (rolled, V (300, 0, 0), "UTIL_AngleDiff takes the short way round")
end)

T.test ("AngleDiff is UTIL_AngleDiff: dest less src, the short way", function ()
	T.eq (Flight.AngleDiff (10, 350), 20)
	T.eq (Flight.AngleDiff (350, 10), -20)
	T.eq (Flight.AngleDiff (180, 0),  -180, "a half turn up is taken down")
	T.eq (Flight.AngleDiff (-180, 0), 180,  "and down, up")
end)

T.finish ()
