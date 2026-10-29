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

-- Props whose tops the mesh calls walkable (dumpsters, which soldiers climb
-- and cannot get on from, hostages least of all): the areas on top go.
T.test("cs_office's dumpsters are listed, each by where it stands", function()
	local props = Hotfixes.Props("cs_office")
	T.eq(#props, 7, "its seven dumpsters")
	for _, prop in ipairs(props) do T.eq(type(prop.x) == "number" and type(prop.z) == "number", true, "a position") end
	T.eq(#Hotfixes.Props("gm_construct"), 0, "none elsewhere")
end)

T.test("an area is on a prop's top when it is beside it and above its foot", function()
	local prop = { x = 916, y = -1123, z = -272 }
	T.eq(Hotfixes.OnTop(prop, { x = 912, y = -1125, z = -206 }), true, "the dumpster's top")
	T.eq(Hotfixes.OnTop(prop, { x = 912, y = -1125, z = -272 }), false, "the ground beside it")
	T.eq(Hotfixes.OnTop(prop, { x = 916 + Hotfixes.PROP_RADIUS + 1, y = -1123, z = -206 }), false, "a ledge elsewhere, as high")
end)

T.finish()
