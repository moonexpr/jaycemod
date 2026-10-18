-- foundation.npc.noise: the noises a walker's body makes, by Source's
-- player rules (CBasePlayer::UpdateStepSound, CGameMovement's landing):
-- footsteps by its speed, a landing by how fast it fell, and how far
-- either carries to a listener (DrGBase's hearing).
local T = dofile("tests/harness.lua")
local Noise = T.require("foundation.npc.noise")

for _, name in ipairs({ "WALK_SPEED", "RUN_SPEED", "CROUCH_WALK_SPEED", "CROUCH_RUN_SPEED", "MIN_BOUNCE_SPEED",
	"MAX_SAFE_FALL_SPEED", "HARD_LANDING_SPEED", "JUMP_LANDING_VOLUME", "HIDDEN_HEARING" }) do
	T.defined(Noise[name], name)
end

T.test("a walker too slow for a step makes none", function()
	T.eq(Noise.Step(Noise.WALK_SPEED - 1, false), nil, "standing")
	T.eq(Noise.Step(Noise.CROUCH_WALK_SPEED - 1, true), nil, "crouched, creeping")
end)

T.test("a runner steps more often and louder than a walker", function()
	local walk, run = Noise.Step(Noise.WALK_SPEED, false), Noise.Step(Noise.RUN_SPEED, false)
	T.eq(run.interval < walk.interval, true, "more often")
	T.eq(run.volume > walk.volume, true, "louder")
	T.eq(Noise.Step(Noise.RUN_SPEED - 1, false).interval, walk.interval, "just under a run is a walk")
end)

T.test("a crouched walker steps quieter, and runs at a lower speed", function()
	local standing, crouched = Noise.Step(Noise.RUN_SPEED, false), Noise.Step(Noise.RUN_SPEED, true)
	T.eq(crouched.volume < standing.volume, true, "quieter")
	T.eq(Noise.Step(Noise.CROUCH_RUN_SPEED, true).interval, standing.interval, "a crouched run")
	T.eq(Noise.Step(Noise.CROUCH_WALK_SPEED, true) ~= nil, true, "steps crouched below a standing walk")
end)

T.test("a landing is silent below a bounce, louder the faster the fall", function()
	T.eq(Noise.Landing(Noise.MIN_BOUNCE_SPEED - 1), 0, "a hop")
	local normal = Noise.Landing(Noise.MIN_BOUNCE_SPEED)
	local hard = Noise.Landing(Noise.MAX_SAFE_FALL_SPEED / 2 + 1)
	local deadly = Noise.Landing(Noise.MAX_SAFE_FALL_SPEED + 1)
	T.eq(normal > 0, true, "a jump's landing")
	T.eq(hard > normal, true, "past half a safe fall")
	T.eq(deadly > hard, true, "past a safe fall")
	T.eq(deadly <= 1, true, "at most full volume")
end)

T.test("a hard landing is one past the screen-punch threshold", function()
	T.eq(Noise.HardLanding(Noise.HARD_LANDING_SPEED), true, "at it")
	T.eq(Noise.HardLanding(Noise.HARD_LANDING_SPEED - 1), false, "under it")
end)

T.test("a noise carries further the louder it is, and half as far unseen", function()
	local range = Noise.HearingRange(75, 1)
	T.eq(Noise.HearingRange(75, 0.5) < range, true, "quieter carries less")
	T.eq(Noise.Hears(75, 1, range, true, 1), true, "at the edge, seen")
	T.eq(Noise.Hears(75, 1, range + 1, true, 1), false, "past it")
	T.eq(Noise.Hears(75, 1, range * Noise.HIDDEN_HEARING + 1, false, 1), false, "unseen, past the shorter range")
	T.eq(Noise.Hears(75, 1, range, true, 0), false, "deaf")
end)

-- Steps and landings play louder than Source's own volumes, to be heard over
-- the fighting: twice as loud, never past full.
T.test("a step plays twice as loud as Source's, at most full volume", function()
	T.eq(Noise.Played(0.2), 0.4, "a walk")
	T.eq(Noise.Played(0.5), 1, "a run: full")
	T.eq(Noise.Played(0.85), 1, "never past full")
end)

T.finish()
