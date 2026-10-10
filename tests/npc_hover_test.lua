local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local Hover = T.require("foundation.npc.hover")

local V = Fake.Vector
local DT = 0.1

local CFG = {
	hoverHeight = 200,
	acceleration = 500,
	horizontalDamping = 2,
	verticalDamping = 1,
}

local function New()
	return Hover.New(CFG, V)
end

local GROUND = 0
local ALIVE, DEAD = true, false

T.test("at its hover height with no goal it stays put", function()
	local h = New()
	local velocity, move = h:Step(DT, V(0, 0, 200), GROUND, ALIVE)
	T.eq(velocity, V(0, 0, 0), "velocity")
	T.eq(move, V(0, 0, 0), "move")
end)

T.test("the climb is clamped to the acceleration", function()
	local h = New()
	local velocity, move = h:Step(DT, V(0, 0, -800), GROUND, ALIVE)
	T.near(velocity.z, CFG.acceleration * DT, 1e-9, "full acceleration up")
	T.near(move.z, CFG.acceleration * DT * DT, 1e-9, "move is velocity times dt")
	h = New()
	velocity = h:Step(DT, V(0, 0, 5000), GROUND, ALIVE)
	T.near(velocity.z, -CFG.acceleration * DT, 1e-9, "full acceleration down")
	h = New()
	velocity = h:Step(DT, V(0, 0, 230), GROUND, ALIVE)
	T.near(velocity.z, -30 * DT, 1e-9, "a small error, unclamped")
end)

T.test("the altitude is measured from the ground below", function()
	local h = New()
	local velocity = h:Step(DT, V(0, 0, 1200), 1000, ALIVE)
	T.near(velocity.z, 0, 1e-9, "200 above a ledge at 1000")
	h:SetDesiredAltitude(100)
	velocity = h:Step(DT, V(0, 0, 1200), 1000, ALIVE)
	T.near(velocity.z, -100 * DT, 1e-9, "a new desired altitude")
end)

T.test("Approach accelerates level towards the goal, for one step only", function()
	local h = New()
	h:Approach(V(300, 400, 5000), V(0, 0, 200))
	local velocity = h:Step(DT, V(0, 0, 200), GROUND, ALIVE)
	T.near(velocity.x, 0.6 * CFG.acceleration * DT, 1e-9, "x")
	T.near(velocity.y, 0.8 * CFG.acceleration * DT, 1e-9, "y")
	T.near(velocity.z, 0, 1e-9, "the goal's height is ignored")
	h:Approach(V(300, 0, 0), V(0, 0, 200))
	h:Approach(V(300, 0, 0), V(0, 0, 200))
	velocity = h:Step(DT, V(0, 0, 200), GROUND, ALIVE)
	local vx = 30 + (2 * CFG.acceleration - 30 * CFG.horizontalDamping) * DT
	T.near(velocity.x, vx, 1e-9, "two approaches in a step add up")
end)

T.test("damping slows the flight horizontally and vertically at their own rates", function()
	local h = New()
	h:Approach(V(100, 0, 0), V(0, 0, 200))
	local velocity = h:Step(DT, V(0, 0, 0), GROUND, ALIVE) -- climbs as well
	T.near(velocity.x, 50, 1e-9, "x after approaching")
	T.near(velocity.z, 20, 1e-9, "z after climbing")
	velocity = h:Step(DT, V(0, 0, 200), GROUND, ALIVE)
	T.near(velocity.x, 50 - 50 * CFG.horizontalDamping * DT, 1e-9, "horizontal damping")
	T.near(velocity.z, 20 - 20 * CFG.verticalDamping * DT, 1e-9, "vertical damping")
	T.near(h:GetGroundSpeed(), 40, 1e-9, "ground speed")
end)

T.test("dead, it falls at 300 units/s/s whatever it was doing", function()
	local h = New()
	h:Approach(V(100, 0, 0), V(0, 0, 200))
	local velocity = h:Step(DT, V(0, 0, 0), GROUND, DEAD)
	T.eq(velocity, V(0, 0, -Hover.FALL_ACCELERATION * DT), "falls")
	T.defined(Hover.FALL_ACCELERATION, "fall")
end)

T.test("a bounce reflects the velocity off the surface", function()
	local h = New()
	h:Approach(V(100, 0, 0), V(0, 0, 200))
	h:Step(DT, V(0, 0, 200), GROUND, ALIVE)
	h:Bounce(V(-1, 0, 0))
	T.eq(h:GetVelocity(), V(-50, 0, 0), "reflected")
end)

T.finish()
