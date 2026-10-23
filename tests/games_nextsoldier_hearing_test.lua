-- Hearing gunfire (games.nextsoldier.hearing): where a soldier who hears a
-- shot turns to look, so its own sight can find the shooter or the fight.
local T = dofile("tests/harness.lua")
local Hearing = T.require("games.nextsoldier.hearing")

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

local function Near(p, q, what)
	T.eq(p ~= nil and math.abs(p.x - q.x) < 1e-6 and math.abs(p.y - q.y) < 1e-6, true, what)
end

local RED, BLUE = 2, 3

T.test("an enemy's shot in earshot: look at the shooter", function()
	local shot = { team = BLUE, pos = P(1000, 0), dir = P(-1, 0) }
	Near(Hearing.LookAt({ team = RED, pos = P(0, 0) }, shot), P(1000, 0), "the shooter")
end)

T.test("an ally's shot in earshot: look where it fires, toward the fight", function()
	local shot = { team = RED, pos = P(500, 0), dir = P(0, 1) }
	Near(Hearing.LookAt({ team = RED, pos = P(0, 0) }, shot), P(500, Hearing.AIM_REACH), "along its aim")
end)

T.test("a shot out of earshot is not heard", function()
	local shot = { team = BLUE, pos = P(Hearing.RANGE + 1, 0), dir = P(-1, 0) }
	T.eq(Hearing.LookAt({ team = RED, pos = P(0, 0) }, shot), nil)
end)

T.test("a shot from no side (no team) is looked at like an enemy's", function()
	local shot = { pos = P(300, 300), dir = P(1, 0) }
	Near(Hearing.LookAt({ team = RED, pos = P(0, 0) }, shot), P(300, 300), "the shooter")
end)

T.finish()
