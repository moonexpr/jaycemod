-- The NextSoldier overlay's parts, each shown or hidden by the viewer's own
-- client convar (the Debug NextSoldier panel's toggles): the soldiers'
-- boxes, routes and goals; each squad's formation round its leader;
-- contacts, flank points and cover; each team's lanes; each team's battle
-- lines (its posts and its front). The boxes' layout is still
-- foundation.aiwar.overlay's (docs/ns-split.md).
module(...)

SOLDIERS, SQUADS, CONTACTS, LANES, BATTLELINES = "soldiers", "squads", "contacts", "lanes", "battlelines"
PARTS = { SOLDIERS, SQUADS, CONTACTS, LANES, BATTLELINES }

-- "ns_lanes_debug"
function ConVar(part)
	return "ns_" .. part .. "_debug"
end
