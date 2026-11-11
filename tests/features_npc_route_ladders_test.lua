-- features.npc.route_ladders: the nav ladders of an area as the route searches' mesh takes them
-- (one link an area reached, none where the floor already goes), and the points a route walks
-- to climb one.
local T = dofile ("tests/harness.lua")
local Ladders = T.require ("features.npc.route_ladders")

T.test ("each area a ladder reaches is one link, by its shortest ladder, in the order met", function ()
	local links = Ladders.Links (
		{
			{ to = 7, length = 300, handle = "long" },
			{ to = 9, length = 120, handle = "other" },
			{ to = 7, length = 200, handle = "short" }
		}, {})
	T.eq (#links,                                                             2,             "two areas reached")
	T.eq (links [1].to .. " " .. links [1].length .. " " .. links [1].handle, "7 200 short", "the shorter ladder to the first")
	T.eq (links [2].to .. " " .. links [2].length .. " " .. links [2].handle, "9 120 other", "then the second")
end)

T.test ("an area the floor already links is no ladder link, nor is the area itself", function ()
	local links = Ladders.Links ({ { to = 7, length = 200, handle = "a" }, { to = 4, length = 90, handle = "b" } }, { [7] = true }, 4)
	T.eq (#links, 0, "the floor's link stands, and a ladder back to its own area is none")
end)

T.test ("a ladder is climbed from before its foot to its head, and down from its head to before its foot", function ()
	local foot, head, out = { x = 100, y = 0, z = 0 }, { x = 100, y = 0, z = 256 }, { x = 1, y = 0, z = 0 }
	local up = Ladders.Points (foot, head, out, true)
	T.eq (#up,                                                             2,                       "two points")
	T.eq (up [1].x > foot.x and up [1].y == foot.y and up [1].z == foot.z, true,                    "it comes to stand out from the ladder's face")
	T.eq (up [2].x .. " " .. up [2].z,                                     head.x .. " " .. head.z, "then its head")
	local down = Ladders.Points (foot, head, out, false)
	T.eq (down [1].z,                                      head.z, "down: from its head")
	T.eq (down [2].x == up [1].x and down [2].z == foot.z, true,   "to where a climber stands before its foot")
	T.defined (Ladders.STAND_OUT, "how far out a body stands")
	T.near (up [1].x - foot.x, Ladders.STAND_OUT, 0.001, "out by that much")
end)

T.finish ()
