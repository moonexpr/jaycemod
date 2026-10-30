-- features.nbdebug.ns_overlay: the NextSoldier overlay's parts, each its own
-- client convar.
local T = dofile("tests/harness.lua")
local Overlay = T.require("features.nbdebug.ns_overlay")

T.test("each part of the overlay has its own client convar, ns_<part>_debug", function()
	local seen = {}
	for _, part in ipairs(Overlay.PARTS) do
		local name = Overlay.ConVar(part)
		T.eq(name:match("^ns_[a-z]+_debug$") ~= nil, true, name)
		T.eq(seen[name], nil, "one convar per part: " .. name)
		seen[name] = true
	end
	T.eq(#Overlay.PARTS, 6, "soldiers, squads, contacts, lanes, battle lines and rooms")
	T.eq(Overlay.ConVar(Overlay.LANES), "ns_lanes_debug", "lanes")
	T.eq(Overlay.ConVar(Overlay.BATTLELINES), "ns_battlelines_debug", "battle lines")
	T.eq(Overlay.ConVar(Overlay.ROOMS), "ns_rooms_debug", "rooms")
end)

T.test("the parts fall in two groups, the soldiers' AI and the tactics engine's planning, each part in one", function()
	T.eq(#Overlay.GROUPS, 2)
	local grouped = {}
	for _, group in ipairs(Overlay.GROUPS) do
		T.eq(type(group.name), "string", "a heading")
		for _, part in ipairs(group.parts) do
			T.eq(grouped[part], nil, "in one group: " .. part)
			grouped[part] = group
		end
	end
	for _, part in ipairs(Overlay.PARTS) do T.eq(grouped[part] ~= nil, true, "grouped: " .. part) end
	T.eq(grouped[Overlay.CONTACTS], Overlay.GROUPS[2], "contacts, flanks and cover are the tactics engine's")
	T.eq(grouped[Overlay.ROOMS], Overlay.GROUPS[2], "so are the rooms and what each team knows of them")
	T.eq(grouped[Overlay.SOLDIERS], Overlay.GROUPS[1], "the soldiers are NextSoldier's")
end)

T.finish()
