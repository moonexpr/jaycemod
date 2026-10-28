-- The kill feed for the AI war's soldiers. GMod's death notices name an NPC
-- "#<class>" with team -1, drawn in a fixed NPC colour; a soldier's notice
-- takes the team its faction fights for instead (features.aiwar.model's
-- factions: the Combine and the Resistance, each on its home team until
-- the sides trade), so it is drawn in that team's colour. A soldier is
-- named by its kind (Notice: every kind is one class, npc_nextsoldier),
-- each given its display name (ws/cl_kill_feed.lua). Control points'
-- captures and defenses have rows of their own, as in TF2 (Objective), and
-- a death to the world credited to an enemy reads "finished off" (Credited).
local concat, floor, ipairs, pairs, sub = table.concat, math.floor, ipairs, pairs, string.sub
local AiWar = require("features.aiwar.model")
local Icons = gameplay.kill_icons
local Teams = gameplay.teams
module(...)

NPC_TEAM = -1 -- the team a death notice gives an NPC

-- kind -> its faction's id
SOLDIERS = {}
for id, faction in pairs(AiWar.FACTIONS) do
	for kind in pairs(faction.kinds) do SOLDIERS[kind] = id end
end

-- A soldier's name in a death notice, as GMod's "#<class>" names an NPC.
function Notice(kind) return "#" .. kind end

-- The team to show a notice's name in: for a soldier's kind ("#<kind>",
-- Notice, or the kind alone), the team its faction fights
-- for in sides (features.aiwar.model's Sides; without it, its home); else the
-- notice's own team, as for a death with no name (nil: a fall, a suicide).
function Team(name, team, sides)
	if team ~= NPC_TEAM or name == nil then return team end
	local kind = sub(name, 1, 1) == "#" and sub(name, 2) or name
	local faction = SOLDIERS[kind]
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

-- A death notice's flag (GMod's byte, beside its DEATH_NOTICE_* bits):
-- the victim died to the environment, credited to the enemy who had hurt
-- it (games.gameplay.kill_credit, TF2's assisted suicide).
FINISHED_OFF = 64

-- CTFHudDeathNotice's assisted suicide: #DeathMsg_AssistedSuicide's words,
-- under TF2's skull, since it has no icon for the world.
local CREDITED = { info = "finished off", icon = Icons.SKULL }

-- What a notice with flags shows of a credited death, { info, icon }, or
-- nil for any other.
function Credited(flags)
	if floor(flags / FINISHED_OFF) % 2 == 1 then return CREDITED end
	return nil
end

-- A death notice's flag: the victim was thrown and slammed dead into a
-- surface (ws/sv_hits.lua's strike), credited to its thrower.
SLAMMED = 128

-- The impact's icon, Sandcastle's own (ws/kill_icons_sheet.lua): a figure
-- slammed into a wall.
IMPACT_ICON = "ws_impact"

-- The icon a notice's flags choose over what struck, or nil for none.
function Icon(flags)
	if floor(flags / SLAMMED) % 2 == 1 then return IMPACT_ICON end
	return nil
end

-- CTFHudDeathNotice's assisted kill: assister (a name, in assisterTeam's
-- colour) joins the killer, "killer + assister"; the row is mine too when
-- I (me, nil while my client loads) assisted. Sets row's fields.
function WithAssister(row, assister, assisterTeam, me)
	row.assister = assister
	row.assisterTeam = assisterTeam
	row.mine = row.mine or (me ~= nil and assister == me)
end

-- Whether a notice is the player's own (me: their name, or nil while their
-- client is still loading and they have none): they killed or died.
function Mine(me, killer, victim)
	return me ~= nil and (killer == me or victim == me)
end
