-- The NextSoldier overlay's parts, each shown or hidden by the viewer's own
-- client convar (the Debug NextSoldier panel's checkboxes and the NPC
-- context menu's toggles, both labelled from LABELS): the soldiers'
-- boxes, routes and goals; each squad's formation round its leader;
-- contacts, flank points and cover; each team's lanes; each team's battle
-- lines (its posts and its front). The boxes' layout is still
-- foundation.aiwar.overlay's (docs/ns-split.md).
module(...)

SOLDIERS, SQUADS, CONTACTS, LANES, BATTLELINES = "soldiers", "squads", "contacts", "lanes", "battlelines"
PARTS = { SOLDIERS, SQUADS, CONTACTS, LANES, BATTLELINES }

LABELS = {
	[SOLDIERS] = "Soldiers: boxes, routes and goals",
	[SQUADS] = "Squads: leaders, formation links and orders",
	[CONTACTS] = "Contacts: enemy last seen, flanks and cover",
	[LANES] = "Lanes: each team's ways in, and who holds them",
	[BATTLELINES] = "Battle lines: posts, fronts and cart spheres",
}

-- The parts by whose thinking they show, each a section of the Debug
-- NextSoldier panel: NextSoldier's AI (its soldiers, squads, and the lanes
-- and battle lines it plans the field with) and the tactics engine's
-- planning (games.ns.tactics: each fire team's contact, flank point
-- and cover).
GROUPS = {
	{
		name = "NextSoldier AI",
		parts = { SOLDIERS, SQUADS, LANES, BATTLELINES },
	},
	{
		name = "Tactics engine planning",
		parts = { CONTACTS },
	},
}

-- "ns_lanes_debug"
function ConVar(part)
	return "ns_" .. part .. "_debug"
end
