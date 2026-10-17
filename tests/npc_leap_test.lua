-- foundation.npc.leap: a walker's jump onto a ledge as an arc it is moved
-- along, from where it stands to past the ledge's lip.
local T = dofile("tests/harness.lua")
local Leap = T.require("foundation.npc.leap")

T.defined(Leap.CLEARANCE, "CLEARANCE")
T.defined(Leap.OVER, "OVER")
T.defined(Leap.DURATION, "DURATION")

local function P(x, y, z) return { x = x, y = y, z = z } end
local function Horizontal(a, b) return math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) end

T.test("the arc starts where the walker stands and ends past the lip, above it", function()
	local from, ledge = P(0, 0, 0), P(20, 0, 40)
	local start, finish = Leap.Arc(from, ledge, 0), Leap.Arc(from, ledge, 1)
	T.eq(start.x, 0, "x at the start")
	T.eq(start.z, 0, "z at the start")
	T.eq(finish.x, 20 + Leap.OVER, "past the lip")
	T.eq(finish.z, 40 + Leap.CLEARANCE, "above it")
end)

-- Wherever the ledge's wall stands between the walker and the lip, the
-- walker's feet are above the lip by the time it gets there; for every
-- ledge a soldier's route may jump.
T.test("the feet are above the lip before the walker reaches the wall", function()
	local HL2 = T.require("foundation.npc.path.hl2")
	local from = P(0, 0, 0)
	for _, height in ipairs({ 19, 30, HL2.SOLDIER_JUMP_HEIGHT - 1 }) do
		for _, reach in ipairs({ 1, 10, 20, 30 }) do
			local ledge = P(reach, 0, height)
			for step = 0, 100 do
				local p = Leap.Arc(from, ledge, step / 100)
				if Horizontal(from, p) >= reach then
					T.eq(p.z >= height, true, string.format("a ledge %d high, %d away, at %d%%", height, reach, step))
					break
				end
			end
		end
	end
end)

T.test("the arc keeps the walker's heading in any direction", function()
	local p = Leap.Arc(P(100, 100, 10), P(100, 80, 50), 1)
	T.eq(p.x, 100, "no sideways drift")
	T.eq(p.y, 80 - Leap.OVER, "on past the lip, along -y")
end)

T.test("a time past the end stays at the end", function()
	local from, ledge = P(0, 0, 0), P(20, 0, 40)
	local late, finish = Leap.Arc(from, ledge, 1.5), Leap.Arc(from, ledge, 1)
	T.eq(late.x, finish.x, "x")
	T.eq(late.z, finish.z, "z")
end)

T.test("a ledge straight above leaves the walker where it is across", function()
	local p = Leap.Arc(P(5, 5, 0), P(5, 5, 40), 1)
	T.eq(p.x, 5, "x")
	T.eq(p.y, 5, "y")
	T.eq(p.z, 40 + Leap.CLEARANCE, "above it")
end)

T.finish()
