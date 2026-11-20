-- nextsoldier.world.nav_stairs: a map's slanted player clips read as stairs, and
-- the ramp that replaces what the nav generator left of one. The fixture is
-- cp_5gorge's staircase: treads of 16 by 16 under a 45 degree clip, on which the
-- generator's 25-unit samples leave fragments and a gap.
local T = dofile ("tests/harness.lua")
local NavStairs = nextsoldier.world.nav_stairs

local ROOT2 = math.sqrt (2) / 2
local CLIP = NavStairs.PLAYER_CLIP

local function Side (x, y, z, dist, bevel)
	return { plane = { normal = { x = x, y = y, z = z }, dist = dist }, bevel = bevel or 0 }
end

-- A brush over the box, with these slanted sides, of these contents.
local function Brush (lo, hi, slants, contents)
	local sides =
	{
		Side (1, 0, 0, hi.x), Side (-1, 0, 0, -lo.x),
		Side (0, 1, 0, hi.y), Side (0, -1, 0, -lo.y),
		Side (0, 0, 1, hi.z), Side (0, 0, -1, -lo.z)
	}
	for _, slant in ipairs (slants) do sides [#sides + 1] = slant end
	return { contents = contents or CLIP, sides = sides }
end

local function P (x, y, z) return { x = x, y = y, z = z } end

-- z = 1264 - y: rising toward lower y
local function GorgeStair ()
	return Brush (P (-6524, 1160, -96), P (-6404, 1360, 104), { Side (0, ROOT2, ROOT2, 1264 * ROOT2) })
end

-- An area of a slope along y: z at its low y and at its high y.
local function Area (id, x0, y0, x1, y1, zLowY, zHighY, links)
	return
	{
		id = id, lo = { x = x0, y = y0 }, hi = { x = x1, y = y1 },
		z = { nw = zLowY, ne = zLowY, se = zHighY, sw = zHighY },
		links = links or {}
	}
end

local function GorgeAreas ()
	return
	{
		Area (36, -6500, 1350, -6425, 1375, -96, -96, { 38 }), -- the floor at the foot
		Area (38, -6500, 1300, -6425, 1325, -48, -64, { 50, 36 }),
		Area (50, -6475, 1250, -6450, 1275, 0, -16, { 38 }),
		Area (42, -6500, 1150, -6425, 1200, 96, 64, {}), -- warped, the flight's last
		Area (77, -6500, 1125, -6425, 1150, 96, 96, {}), -- the landing
		Area (80, -6500, 1250, -6450, 1275, -96, -96, {}), -- the floor under the stairs
		Area (99, -6000, 1200, -5900, 1300, 0, 0, {}) -- elsewhere
	}
end

local function Sorted (list)
	local copy = {}
	for i, value in ipairs (list) do copy [i] = value end
	table.sort (copy)
	return table.concat (copy, ",")
end

T.defined (NavStairs.PLAYER_CLIP, "PLAYER_CLIP")

T.test ("a player clip slanted along one axis is a stair: which way it runs and rises", function ()
	local slope = NavStairs.Slope (GorgeStair ())
	T.eq (slope.along,  "y")
	T.eq (slope.across, "x")
	T.eq (slope.rising, -1, "up toward lower y")
	T.eq (slope.lo.x .. "," .. slope.hi.x, "-6524,-6404")
	T.near (NavStairs.Surface (slope, -6463, 1264), 0, 0.01)
end)

T.test ("a clip among other contents is still a clip, and other brushes are no stairs", function ()
	local detail = GorgeStair ()
	detail.contents = CLIP + 0x8000000
	T.eq (NavStairs.Slope (detail) ~= nil, true, "a detail clip")
	local solid = GorgeStair ()
	solid.contents = 1
	T.eq (NavStairs.Slope (solid), nil, "a solid slope")
end)

T.test ("what no body climbs as a stair is refused", function ()
	local rail = Brush (P (-6524, 1160, -96), P (-6520, 1360, 104), { Side (0, ROOT2, ROOT2, 1264 * ROOT2) })
	T.eq (NavStairs.Slope (rail), nil, "narrower than a body")
	local kerb = Brush (P (-6524, 1256, -96), P (-6404, 1264, 8), { Side (0, ROOT2, ROOT2, 1264 * ROOT2) })
	T.eq (NavStairs.Slope (kerb), nil, "rising no more than a step")
	local flat = Brush (P (-6524, 1160, -96), P (-6404, 1360, 104), {})
	T.eq (NavStairs.Slope (flat), nil, "no slant")
	local diagonal = Brush (P (-6524, 1160, -96), P (-6404, 1360, 104), { Side (0.5, 0.5, ROOT2, 0) })
	T.eq (NavStairs.Slope (diagonal), nil, "slanted across both axes: no nav area lies along it")
	local steep = Brush (P (-6524, 1160, -96), P (-6404, 1360, 104), { Side (0, 0.9, math.sqrt (1 - 0.81), 1000) })
	T.eq (NavStairs.Slope (steep), nil, "too steep to stand on")
	local beveled = Brush (P (-6524, 1160, -96), P (-6404, 1360, 104), { Side (0, ROOT2, ROOT2, 1264 * ROOT2, 1) })
	T.eq (NavStairs.Slope (beveled), nil, "a bevel is no face")
	local peak = Brush (P (-6524, 1160, -96), P (-6404, 1360, 104),
		{ Side (0, ROOT2, ROOT2, 1264 * ROOT2), Side (0, -ROOT2, ROOT2, 0) })
	T.eq (NavStairs.Slope (peak), nil, "a roof's two slants")
end)

T.test ("Slopes keeps a map's stairs and drops the rest", function ()
	local solid = GorgeStair ()
	solid.contents = 1
	T.eq (#NavStairs.Slopes ({ GorgeStair (), solid, GorgeStair () }), 2)
end)

T.test ("a broken flight becomes one ramp between the floor and the landing", function ()
	local plan = NavStairs.Plan (NavStairs.Slope (GorgeStair ()), GorgeAreas ())
	T.eq (Sorted (plan.remove), "38,42,50", "what lies warped on the flight goes; the floor under the stairs stays")
	T.eq (Sorted (plan.connect), "36,77", "the floor and the landing")
	T.eq (plan.lo.x .. "," .. plan.hi.x, "-6500,-6425", "as wide as the fragments, not the clip")
	T.eq (plan.lo.y .. "," .. plan.hi.y, "1150,1350", "from the foot's edge to the landing's")
	T.near (plan.z.nw, 96, 0.01, "no higher than the landing")
	T.near (plan.z.ne, 96, 0.01)
	T.near (plan.z.sw, -86, 0.01, "on the clip, above the floor")
	T.near (plan.z.se, -86, 0.01)
end)

T.test ("an area warped across the flight's foot is no floor, and goes with the rest", function ()
	local slope = NavStairs.Slope (GorgeStair ())
	local plan = NavStairs.Plan (slope,
		{
			Area (10, -6500, 1375, -6425, 1400, -96, -96, { 11 }), -- the floor
			Area (11, -6500, 1325, -6425, 1375, -64, -96, { 10 }), -- warped, over the foot
			Area (77, -6500, 1125, -6425, 1150, 96, 96, {})
		}
	)
	T.eq (Sorted (plan.remove),          "11")
	T.eq (Sorted (plan.connect),         "10,77")
	T.eq (plan.lo.y .. "," .. plan.hi.y, "1150,1375")
end)

T.test ("a floor running on under the flight is joined where the clip rises from it, not under the stairs", function ()
	local slope = NavStairs.Slope (GorgeStair ())
	local plan = NavStairs.Plan (slope,
		{
			Area (10, -6500, 1130, -6425, 1400, -96, -96, {}),
			Area (77, -6500, 1125, -6425, 1150, 96, 96, {})
		}
	)
	T.eq (Sorted (plan.connect), "10,77")
	T.near (plan.z.sw - (-96), 18, 0.01, "within a step of the floor")
end)

T.test ("the row nearest the foot is the one joined, not a floor farther off", function ()
	local slope = NavStairs.Slope (GorgeStair ())
	local plan = NavStairs.Plan (slope,
		{
			Area (36, -6500, 1350, -6425, 1375, -96, -96, {}),
			Area (15, -6500, 1380, -6425, 1400, -96, -96, {}),
			Area (77, -6500, 1125, -6425, 1150, 96, 96, {})
		}
	)
	T.eq (Sorted (plan.connect), "36,77")
end)

T.test ("a ramp already laid needs no repair, so a repaired map is not saved again", function ()
	local slope = NavStairs.Slope (GorgeStair ())
	local plan = NavStairs.Plan (slope, GorgeAreas ())
	local foot = Area (36, -6500, 1350, -6425, 1375, -96, -96, { 1 })
	local ramp = { id = 1, lo = plan.lo, hi = plan.hi, z = plan.z, links = { 36, 77 } }
	local landing = Area (77, -6500, 1125, -6425, 1150, 96, 96, { 1 })
	T.eq (NavStairs.Plan (slope, { foot, ramp, landing }), nil)
end)

T.test ("a ramp already over the planned footprint is not laid again, whatever its links", function ()
	local slope = NavStairs.Slope (GorgeStair ())
	local plan = NavStairs.Plan (slope, GorgeAreas ())
	local foot = Area (36, -6500, 1350, -6425, 1375, -96, -96, {})
	local ramp = { id = 1, lo = plan.lo, hi = plan.hi, z = plan.z, links = {} }
	local landing = Area (77, -6500, 1125, -6425, 1150, 96, 96, {})
	T.eq (NavStairs.Plan (slope, { foot, ramp, landing }), nil)
end)

T.test ("a floor overlapping the flight by less than a walker's width is no end of it", function ()
	local slope = NavStairs.Slope (GorgeStair ()) -- x from -6524
	T.eq (NavStairs.Plan (slope,
		{
			Area (36, -6600, 1350, -6517, 1375, -96, -96, {}),
			Area (77, -6500, 1125, -6425, 1150, 96, 96, {})
		}
	), nil, "7 of it at the foot")
end)

T.test ("a flight whose links walk but whose areas lie far under the clip is repaired again", function ()
	local slope = NavStairs.Slope (GorgeStair ())
	local plan = NavStairs.Plan (slope,
		{
			Area (10, -6500, 1375, -6425, 1400, -96, -96, { 11 }),
			Area (11, -6500, 1325, -6425, 1375, -80, -96, { 10, 12 }), -- 19 below the clip at its upper edge
			Area (12, -6500, 1150, -6425, 1325, 96, -80, { 11, 77 }),
			Area (77, -6500, 1125, -6425, 1150, 96, 96, { 12 })
		}
	)
	T.eq (Sorted (plan.remove), "11,12")
end)

T.test ("a flight linked only by jumps is still broken", function ()
	local slope = NavStairs.Slope (GorgeStair ())
	local areas =
	{
		Area (36, -6500, 1350, -6425, 1375, -96, -96, { 38 }),
		Area (38, -6500, 1300, -6425, 1325, -48, -64, { 50, 36 }),
		Area (50, -6500, 1250, -6425, 1275, 0, -16, { 42, 38 }),
		Area (42, -6500, 1150, -6425, 1200, 96, 64, { 50, 77 }),
		Area (77, -6500, 1125, -6425, 1150, 96, 96, { 42 })
	}
	T.eq (Sorted (NavStairs.Plan (slope, areas).remove), "38,42,50", "rises of 32 are no walk")
end)

T.test ("a stair with no floor at either end is left alone", function ()
	local slope = NavStairs.Slope (GorgeStair ())
	T.eq (NavStairs.Plan (slope,
		{
			Area (38, -6500, 1300, -6425, 1325, -48, -64, {}),
			Area (42, -6500, 1150, -6425, 1200, 96, 64, {})
		}
	), nil, "no foot")
	T.eq (NavStairs.Plan (slope,
		{
			Area (36, -6500, 1350, -6425, 1375, -96, -96, {}),
			Area (38, -6500, 1300, -6425, 1325, -48, -64, {})
		}
	), nil, "no landing")
end)

T.test ("a flight with nothing on it is bridged as wide as its ends meet", function ()
	local plan = NavStairs.Plan (NavStairs.Slope (GorgeStair ()),
		{
			Area (36, -6500, 1350, -6425, 1375, -96, -96, {}),
			Area (77, -6475, 1125, -6400, 1150, 96, 96, {})
		}
	)
	T.eq (#plan.remove,                  0)
	T.eq (plan.lo.x .. "," .. plan.hi.x, "-6475,-6425")
end)

T.test ("a stair along x rising toward higher x", function ()
	-- z = x - 1000
	local brush = Brush (P (1000, 0, 0), P (1200, 100, 200), { Side (-ROOT2, 0, ROOT2, -1000 * ROOT2) })
	local slope = NavStairs.Slope (brush)
	T.eq (slope.along,  "x")
	T.eq (slope.rising, 1)
	local function AlongX (id, x0, x1, zLowX, zHighX, links)
		return
		{
			id = id, lo = { x = x0, y = 10 }, hi = { x = x1, y = 90 },
			z = { nw = zLowX, sw = zLowX, ne = zHighX, se = zHighX }, links = links or {}
		}
	end
	local plan = NavStairs.Plan (slope,
		{
			AlongX (1, 975, 1025, 0, 0, { 2 }),
			AlongX (2, 1075, 1100, 75, 100, { 1 }),
			AlongX (3, 1200, 1225, 200, 200, {})
		}
	)
	T.eq (Sorted (plan.remove), "2")
	T.eq (plan.lo.x .. "," .. plan.hi.x, "1018,1200", "where the clip is a step above the floor")
	T.near (plan.z.nw, 18,  0.01)
	T.near (plan.z.sw, 18,  0.01)
	T.near (plan.z.ne, 200, 0.01)
	T.near (plan.z.se, 200, 0.01)
end)

T.finish ()
