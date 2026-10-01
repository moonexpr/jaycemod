-- foundation.ns.overlay: the NextSoldier overlay's parts, each its own
-- client convar.
local T = dofile("tests/harness.lua")
local Overlay = T.require("foundation.ns.overlay")

T.test("each part of the overlay has its own client convar, ns_<part>_debug", function()
	local seen = {}
	for _, part in ipairs(Overlay.PARTS) do
		local name = Overlay.ConVar(part)
		T.eq(name:match("^ns_[a-z]+_debug$") ~= nil, true, name)
		T.eq(seen[name], nil, "one convar per part: " .. name)
		seen[name] = true
	end
	T.eq(#Overlay.PARTS, 5, "soldiers, squads, contacts, lanes and battle lines")
	T.eq(Overlay.ConVar(Overlay.LANES), "ns_lanes_debug", "lanes")
	T.eq(Overlay.ConVar(Overlay.BATTLELINES), "ns_battlelines_debug", "battle lines")
end)

T.finish()
