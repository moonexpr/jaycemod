-- nextsoldier.gaze: where a soldier's head looks apart from its aim (the
-- player model's head_yaw and head_pitch over aim_yaw and aim_pitch): along
-- its aim in a fight; else where it was told to look (a repath's new way);
-- else the nearest person passing it; else ahead; never past what a head
-- turns.
local T = dofile("tests/harness.lua")
local Gaze = nextsoldier.gaze

local EYE = { x = 0, y = 0, z = 64 }
local function P(x, y, z) return { x = x, y = y, z = z or 64 } end

T.test("the tuning is defined", function()
	T.defined(Gaze.YAW_LIMIT, "YAW_LIMIT")
	T.defined(Gaze.PITCH_LIMIT, "PITCH_LIMIT")
	T.defined(Gaze.LOOK_RANGE, "LOOK_RANGE")
	T.defined(Gaze.HINT_SECONDS, "HINT_SECONDS")
	T.defined(Gaze.TURN_RATE, "TURN_RATE")
	T.eq(Gaze.YAW_LIMIT, 75, "a head turns 75 degrees either way")
end)

T.test("a point's yaw is from the way the body faces, left positive, as Source's", function()
	T.near(Gaze.Toward(EYE, 0, P(100, 0)), 0, 1e-9, "ahead")
	T.near(Gaze.Toward(EYE, 0, P(100, 100)), 45, 1e-9, "to the left")
	T.near(Gaze.Toward(EYE, 0, P(100, -100)), -45, 1e-9, "to the right")
	T.near(Gaze.Toward(EYE, 90, P(0, 100)), 0, 1e-9, "ahead of a body facing 90")
	T.near(Gaze.Toward(EYE, 170, P(-100, -30)), 26.69924423, 1e-6, "across the wrap at 180")
end)

T.test("a point's pitch is Source's: below the eye positive", function()
	local _, down = Gaze.Toward(EYE, 0, P(100, 0, -36))
	T.near(down, 45, 1e-9)
	local _, up = Gaze.Toward(EYE, 0, P(100, 0, 164))
	T.near(up, -45, 1e-9)
end)

T.test("pitch is held to what a head tilts", function()
	local _, pitch = Gaze.Toward(EYE, 0, P(1, 0, -1000))
	T.eq(pitch, Gaze.PITCH_LIMIT)
end)

T.test("a point past what a head turns is not looked at", function()
	T.eq(Gaze.Toward(EYE, 0, P(10, 100)), nil, "beside")
	T.eq(Gaze.Toward(EYE, 0, P(-100, 0)), nil, "behind")
	local edge = { x = math.cos(math.rad(Gaze.YAW_LIMIT)) * 100, y = math.sin(math.rad(Gaze.YAW_LIMIT)) * 100, z = 64 }
	T.eq(Gaze.Toward(EYE, 0, edge) ~= nil, true, "at the limit")
end)

local function View(fields)
	fields.eye, fields.facing, fields.people = EYE, 0, fields.people or {}
	return fields
end

T.test("in a fight the head looks along the aim", function()
	local yaw, pitch = Gaze.Goal(View({ fighting = true, hint = P(100, 50), people = { P(50, 20) } }))
	T.eq(yaw, 0)
	T.eq(pitch, 0)
end)

T.test("told where to look, it looks there over anyone passing", function()
	local yaw = Gaze.Goal(View({ hint = P(100, 100), people = { P(50, -20) } }))
	T.near(yaw, 45, 1e-9)
end)

T.test("a hint past what a head turns gives way to whoever passes", function()
	local yaw = Gaze.Goal(View({ hint = P(-100, 0), people = { P(50, -50) } }))
	T.near(yaw, -45, 1e-9)
end)

T.test("it looks at the nearest person within LOOK_RANGE that it can turn to", function()
	local near, far = P(Gaze.LOOK_RANGE / 2, Gaze.LOOK_RANGE / 2), P(Gaze.LOOK_RANGE / 2, -Gaze.LOOK_RANGE / 4)
	local behind = P(-10, 0)
	T.near(Gaze.Goal(View({ people = { far, behind } })), Gaze.Toward(EYE, 0, far), 1e-9, "behind is skipped")
	local nearer = P(20, 20)
	T.near(Gaze.Goal(View({ people = { far, nearer } })), 45, 1e-9, "the nearer")
	T.eq(Gaze.Goal(View({ people = { P(Gaze.LOOK_RANGE + 1, 0) } })), 0, "out of range: ahead")
end)

T.test("with nothing to look at it looks ahead", function()
	local yaw, pitch = Gaze.Goal(View({}))
	T.eq(yaw, 0)
	T.eq(pitch, 0)
end)

T.test("the head turns toward its goal at most step, and stops on it", function()
	T.eq(Gaze.Approach(0, 30, 10), 10)
	T.eq(Gaze.Approach(0, -30, 10), -10)
	T.eq(Gaze.Approach(25, 30, 10), 30, "no overshoot")
	T.eq(Gaze.Approach(30, 30, 10), 30)
end)

T.test("the head turns as fast as an HL2MP player's", function()
	T.eq(Gaze.TURN_RATE, 130)
	T.eq(Gaze.Step(0.5, false), 65)
end)

T.test("an urgent look snaps the head onto its goal at once", function()
	local step = Gaze.Step(0.001, true)
	T.eq(Gaze.Approach(-40, 70, step), 70)
	T.eq(Gaze.Turn(-40, 70, step, 0), 70)
end)

T.test("a turning body does not drag the head: it turns back by what the body turned", function()
	T.eq(Gaze.Turn(20, 20, 10, 15), 5, "the body turned left 15 under a head on its goal")
	T.eq(Gaze.Turn(0, 30, 10, 0), 10, "a still body: as Approach")
end)

T.test("a head turned back past what it turns is held there", function()
	T.eq(Gaze.Turn(-70, -70, 10, 30), -Gaze.YAW_LIMIT)
	T.eq(Gaze.Turn(70, 70, 10, -30), Gaze.YAW_LIMIT)
end)

T.finish()
