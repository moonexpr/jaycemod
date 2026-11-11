-- arena_lumberyard_event's graveyard.nut, as rules: after setup the dead come
-- back as ghosts who heal their team, a team's last player alive is announced,
-- and a team with nobody left alive loses (CheckWinState). The controller
-- (features/graveyard/sv.lua) carries out what Check answers.
local Teams = gameplay.teams
local ipairs, min, setmetatable = ipairs, math.min, setmetatable
module (...)

LAST_MAN, WIN, STALEMATE = "last_man", "win", "stalemate"

-- The pd_dispenser each ghost carries: its touch trigger's reach, and a level
-- one dispenser's healing.
HEAL_RADIUS = 128
HEAL_PER_SECOND = 10

-- What the map's RunScriptCode inputs ask for: the text to show everyone
-- (tf_english's arena_lumberyard_event_spell).
CODE =
{
	["printSpellMessage()"] = "A Rare Spell is spawning in a random location!"
}

local RED, BLUE = Teams.RED, Teams.BLUE
local TEAMS = { RED, BLUE }

local Game = {}
Game.__index = Game

function New ()
	return setmetatable ({ setupFinished = false, announced = {}, decided = false }, Game)
end

function Game:FinishSetup () self.setupFinished = true end

-- Whether a player of team spawning now comes back as a ghost.
function Game:GhostOnSpawn (team)
	return self.setupFinished and Teams.EnemyOf (team) ~= nil
end

-- living, members: team -> how many are alive and not ghosts, and how many
-- play on it at all. A team with no players decides nothing: TF2 never starts
-- a round without both teams, and Sandcastle may. -> events, each { kind, team }.
function Game:Check (living, members)
	local events = {}
	if not self.setupFinished or self.decided or members [RED] == 0 or members [BLUE] == 0 then return events end
	for _, team in ipairs (TEAMS) do
		if living [team] == 1 and not self.announced [team] then
			self.announced [team] = true
			events [#events + 1] = { kind = LAST_MAN, team = team }
		end
	end
	if living [RED] > 0 and living [BLUE] > 0 then return events end
	self.decided = true
	if living [RED] == 0 and living [BLUE] == 0 then
		events [#events + 1] = { kind = STALEMATE }
	else
		events [#events + 1] = { kind = WIN, team = living [RED] == 0 and BLUE or RED }
	end
	return events
end

function Healed (health, maxHealth, seconds)
	return min (maxHealth, health + HEAL_PER_SECOND * seconds)
end
