-- nextsoldier.player.sandbox.blockout: a base laid out as blocks, the first pass of a sandbox
-- player's build: four walls of upright plates round a square on a site, a doorway in the
-- front, and where it stands to hold it. Pure: points and angles as plain tables.
local T = dofile ("tests/harness.lua")
local Blockout = nextsoldier.player.sandbox.blockout

local SPEC = { size = 3, height = 2, block = 100, model = "plate.mdl" }

local function Count (blocks, keep)
	local n = 0
	for _, block in ipairs (blocks) do
		if keep (block) then n = n + 1 end
	end
	return n
end

T.test ("a base is four walls of size x height plates, less its doorway's column", function ()
	local blocks = Blockout.Plan ({ x = 0, y = 0, z = 0 }, 0, SPEC)
	T.eq (#blocks,          4 * 3 * 2 - 2, "22 plates")
	T.eq (blocks [1].model, "plate.mdl",   "of its model")
end)

T.test ("its walls stand half the square out from the site, its rows a block apart", function ()
	local blocks = Blockout.Plan ({ x = 1000, y = 0, z = 50 }, 0, SPEC)
	T.eq (Count (blocks, function (b) return b.pos.x == 1000 + 150 end), 4,  "the front, less its doorway")
	T.eq (Count (blocks, function (b) return b.pos.x == 1000 - 150 end), 6,  "the back")
	T.eq (Count (blocks, function (b) return b.pos.y == 150 end),        6,  "the left")
	T.eq (Count (blocks, function (b) return b.pos.y == -150 end),       6,  "the right")
	T.eq (Count (blocks, function (b) return b.pos.z == 50 + 50 end),    11, "a row on the ground")
	T.eq (Count (blocks, function (b) return b.pos.z == 50 + 150 end),   11, "a row on it")
end)

T.test ("the doorway is the front's middle, the way it faces", function ()
	local blocks = Blockout.Plan ({ x = 0, y = 0, z = 0 }, 0, SPEC)
	T.eq (Count (blocks, function (b) return b.pos.x == 150 and b.pos.y == 0 end), 0, "open")
	local door = Blockout.Door ({ x = 0, y = 0, z = 0 }, 0, SPEC)
	T.eq (door.x, 150, "in the front wall")
	T.eq (door.y, 0,   "at its middle")
end)

T.test ("turned, it turns about its site", function ()
	local blocks = Blockout.Plan ({ x = 0, y = 0, z = 0 }, 90, SPEC)
	local door = Blockout.Door ({ x = 0, y = 0, z = 0 }, 90, SPEC)
	T.near (door.x, 0,   1e-6, "faces +y")
	T.near (door.y, 150, 1e-6, "faces +y")
	T.eq (Count (blocks, function (b) return math.abs (b.pos.y - 150) < 1e-6 end), 4, "the front, less its doorway")
end)

T.test ("each plate stands upright, square to its wall", function ()
	local blocks = Blockout.Plan ({ x = 0, y = 0, z = 0 }, 30, SPEC)
	for _, block in ipairs (blocks) do
		T.eq (block.ang.p,      0,       "level")
		T.eq (block.ang.r,      90,      "on its edge")
		T.eq (block.ang.y % 90, 30 % 90, "square to the base")
	end
	local front = Blockout.Plan ({ x = 0, y = 0, z = 0 }, 0, SPEC) [1]
	T.eq (front.ang.y, 90, "a front plate faces out along the way the base faces")
end)

T.test ("its footprint is its square", function ()
	T.eq (Blockout.Footprint (SPEC), 300, "3 blocks of 100")
end)

T.test ("a spec that is not one is refused", function ()
	local site = { x = 0, y = 0, z = 0 }
	T.eq (pcall (Blockout.Plan, site, 0, { size = 0, height = 1, block = 1, model = "m" }), false, "no size")
	T.eq (pcall (Blockout.Plan, site, 0, { size = 3, height = 1, block = 1 }),              false, "no model")
end)

T.finish ()
