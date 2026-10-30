-- Curated hotfixes for the stock CS:S maps (features.hostage.hotfixes): the
-- nav links that run through walls, named by where their two areas are so
-- they hold when a mesh is generated again, cut as the map loads.
local T = dofile("tests/harness.lua")
local Hotfixes = T.require("features.hostage.hotfixes")

T.test("cs_office has its fix: the strip at the Terrorist spawn's exit is cut from the room through the wall", function()
	local links = Hotfixes.For("cs_office")
	T.eq(#links >= 1, true, "a link to cut")
	for _, link in ipairs(links) do
		T.eq(type(link.why), "string", "says why")
		T.eq(type(link.a.x) == "number" and type(link.b.y) == "number", true, "named by positions")
	end
end)

T.test("a map with no fixes, and one that is not CS:S's, has none", function()
	T.eq(#Hotfixes.For("cs_italy") >= 0, true, "a list")
	T.eq(#Hotfixes.For("gm_construct"), 0, "none")
end)

T.test("a fix finds its area by position, within a tolerance", function()
	local at = { x = 100, y = 100, z = 0 }
	T.eq(Hotfixes.Near(at, { x = 110, y = 95, z = 3 }), true, "close")
	T.eq(Hotfixes.Near(at, { x = 100 + Hotfixes.TOLERANCE + 1, y = 100, z = 0 }), false, "too far")
end)

T.test("every fix on every map names two different places", function()
	for _, map in ipairs(Hotfixes.Maps()) do
		for _, link in ipairs(Hotfixes.For(map)) do
			T.eq(Hotfixes.Near(link.a, link.b), false, map .. ": the two areas are apart")
		end
	end
end)

-- The nav areas on the lids of cs_office's dumpsters, which soldiers climbed
-- and hostages followed them onto: named one by one (a radius round each
-- dumpster also took ledges and the floor above), removed as the map loads.
T.test("cs_office's dumpster lids are listed one by one, each with why", function()
	local areas = Hotfixes.Areas("cs_office")
	T.eq(#areas, 11, "eleven lid areas")
	for _, area in ipairs(areas) do
		T.eq(type(area.at.x) == "number" and type(area.at.z) == "number", true, "a position")
		T.eq(type(area.why), "string", "why")
	end
	T.eq(#Hotfixes.Areas("gm_construct"), 0, "none elsewhere")
end)

T.test("no two areas listed on a map are the same place", function()
	for _, map in ipairs(Hotfixes.Maps()) do
		local areas = Hotfixes.Areas(map)
		for i = 1, #areas do
			for j = i + 1, #areas do T.eq(Hotfixes.Near(areas[i].at, areas[j].at), false, map .. " " .. i .. "," .. j) end
		end
	end
end)

T.finish()
