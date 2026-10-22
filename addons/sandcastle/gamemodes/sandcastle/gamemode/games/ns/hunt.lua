-- The hunt: post-round carnage (TF2's CTFBotSeekAndDestroy while the round
-- is won). The winners hunt the losers down, knowing only what they saw:
-- each hunter reports the losers it sees on its team's board, and every
-- hunter goes for the nearest sighting still fresh, else to the losers'
-- spawns. Routes refuse enemy spawn rooms, so a trip to a losers' spawn
-- ends at its door (TF2's spawn-room thresholds). The losers run from what
-- they see and otherwise hide at their own spawn (foundation.aiwar.orders'
-- Humiliated).
--
-- Subjects are opaque enemy handles; positions are { x, y, z } tables.
local ipairs, pairs, setmetatable, sort = ipairs, pairs, setmetatable, table.sort
local Teams = require("games.gameplay.teams")
local Distance = require("foundation.math.geometry").Distance
module(...)

-- A sighting of a loser is followed this long.
HUNT_MEMORY = 10
-- A hunt trip arrives this close, and gives a goal up after this long.
HUNT_ARRIVE, HUNT_GIVE_UP = 96, 12
-- A loser flees to cover within FLEE_COVER of it, picks again when its
-- threat has moved FLEE_REPICK, and has hidden within HIDE_ARRIVE of its
-- spawn.
FLEE_COVER, FLEE_REPICK, HIDE_ARRIVE = 600, 256, 160

local ENEMY = {
	[Teams.RED] = Teams.BLUE,
	[Teams.BLUE] = Teams.RED,
}

local function Nearest(points, here)
	local best, bestDistance
	for _, p in ipairs(points) do
		local d = Distance(p, here)
		if not bestDistance or d < bestDistance then best, bestDistance = p, d end
	end
	return best
end

-------------------------------------------------------------------------------
-- Board: each team's latest sighting of each enemy

Board = {}
Board.__index = Board

function Board.New()
	return setmetatable({ seen = {} }, Board)
end

-- A soldier of `team` saw `subject` at `pos`.
function Board:Report(team, subject, pos, now)
	local seen = self.seen[team] or {}
	self.seen[team] = seen
	seen[subject] = {
		subject = subject,
		pos = pos,
		time = now,
	}
end

-- The team's sightings within HUNT_MEMORY, newest first; older ones are
-- forgotten.
function Board:Sightings(team, now)
	local seen = self.seen[team] or {}
	local list = {}
	for subject, sighting in pairs(seen) do
		if now - sighting.time <= HUNT_MEMORY then
			list[#list + 1] = sighting
		else
			seen[subject] = nil
		end
	end
	sort(list, function(a, b) return a.time > b.time end)
	return list
end

-- The nearest sighting to here, or nil.
function Quarry(sightings, here)
	local best, bestDistance
	for _, sighting in ipairs(sightings) do
		local d = Distance(sighting.pos, here)
		if not bestDistance or d < bestDistance then best, bestDistance = sighting, d end
	end
	return best
end

-- Where a winner hunts: its quarry, else the member's pick of the losers'
-- spawns (by slot, so the hunters spread over them); nil with neither.
function HuntGoal(field, member, sightings, here)
	local quarry = Quarry(sightings, here)
	if quarry then return quarry.pos end
	local spawns = field.spawns and field.spawns[ENEMY[member.team]]
	if not spawns or #spawns == 0 then return nil end
	return spawns[member.slot % #spawns + 1]
end

-- Where a loser hides: the nearest of its own team's spawns, or nil.
function Hideout(field, member, here)
	local spawns = field.spawns and field.spawns[member.team]
	if not spawns then return nil end
	return Nearest(spawns, here)
end
