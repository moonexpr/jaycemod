-- The kill feed for the AI war's soldiers. GMod's death notices name an NPC
-- "#<class>" with team -1, drawn in a fixed NPC colour; a soldier's notice
-- takes the team its faction fights for instead (foundation.aiwar's
-- factions: the Combine and the Resistance, each on its home team until
-- the sides trade), so it is drawn in that team's colour, and each class
-- is given its display name (ws/cl_kill_feed.lua). Control points'
-- captures and defenses have rows of their own, as in TF2 (Objective).
local concat, ipairs, pairs, sub = table.concat, ipairs, pairs, string.sub
local AiWar = require("foundation.aiwar")
local Teams = require("foundation.teams")
module(...)

NPC_TEAM = -1 -- the team a death notice gives an NPC

-- class -> its faction's id
SOLDIERS = {}
for id, faction in pairs(AiWar.FACTIONS) do
	for class in pairs(faction.classes) do SOLDIERS[class] = id end
end

-- The team to show a notice's name in: for a soldier's class ("<class>" as
-- GMod's feed passes an entity, or "#<class>"), the team its faction fights
-- for in sides (foundation.aiwar's Sides; without it, its home); else the
-- notice's own team, as for a death with no name (nil: a fall, a suicide).
function Team(name, team, sides)
	if team ~= NPC_TEAM or name == nil then return team end
	local class = sub(name, 1, 1) == "#" and sub(name, 2) or name
	local faction = SOLDIERS[class]
	if not faction then return team end
	return sides and sides[faction] or AiWar.FACTIONS[faction].home
end

-- An objective's row: a point captured or defended.
CAPTURED, DEFENDED = "captured", "defended"

-- TF2's icons for them, by team (CTFHudDeathNotice::OnGameEvent's
-- d_redcapture and the rest, named in scripts/mod_textures.txt without d_).
OBJECTIVE_ICONS = {
	[CAPTURED] = { [Teams.RED] = "redcapture", [Teams.BLUE] = "bluecapture" },
	[DEFENDED] = { [Teams.RED] = "reddefend", [Teams.BLUE] = "bluedefend" },
}

-- TF2's capture and defense rows (CHudBaseDeathNotice::FireGameEvent): kind
-- CAPTURED or DEFENDED by team, names who did it (several joined by ", ";
-- the team's name, teamName, when none is known) in the team's colour, the
-- team's icon, the word, then point; mine when I (me, nil while my client
-- loads) am among the names. The kill feed's row fields, its icon by name.
function Objective(kind, team, names, teamName, point, me)
	local mine = false
	for _, name in ipairs(names) do
		if me ~= nil and name == me then mine = true end
	end
	return {
		killer = #names > 0 and concat(names, ", ") or teamName,
		killerTeam = team,
		icon = OBJECTIVE_ICONS[kind][team],
		info = kind,
		victim = point,
		victimTeam = Teams.UNASSIGNED,
		mine = mine,
	}
end

-- Whether a notice is the player's own (me: their name, or nil while their
-- client is still loading and they have none): they killed or died.
function Mine(me, killer, victim)
	return me ~= nil and (killer == me or victim == me)
end
