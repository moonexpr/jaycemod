-- The ready-up while a game waits for players (games.system.gamemode's
-- WAITING), TF2's two kinds: every mode's teams ready as a whole, as a
-- tournament's do (CTFGameRules::IsTeamReady), and end the wait early once
-- every team with players on it is ready; MvM's defenders ready each
-- (IsPlayerReady), and its wait ends once its players are there and every
-- defender is ready, the toggle enabled only once they are there
-- (PlayerReadyStatus_HaveMinPlayersToEnable). The controller keeps who is
-- ready (features/gamemode/sv.lua); the panel says it
-- (features.gamemode.tournament).
local ipairs = ipairs
local Teams = gameplay.teams
module(...)

TEAM, PLAYER = "team", "player"

local GAME_TEAMS = { Teams.RED, Teams.BLUE }

function Kind(mvm)
	return mvm and PLAYER or TEAM
end

local function TeamsReady(q)
	local anyone = false
	for _, t in ipairs(GAME_TEAMS) do
		if q.humans[t] > 0 then
			if not q.teamReady[t] then return false end
			anyone = true
		end
	end
	return anyone
end

-- q = { kind, have and need (the round mode's player requirement), humans
-- (by team: the human players on it), teamReady (by team), defenders (the
-- team MvM's players ready on), readyDefenders (how many of its humans are
-- ready) }. Whether the wait is over.
function Met(q)
	if q.kind == PLAYER then return q.have >= q.need and q.readyDefenders >= q.humans[q.defenders] end
	return q.have >= q.need or TeamsReady(q)
end

-- Whether the ready toggle does anything yet (q as Met takes it).
function Enabled(q)
	return q.kind == TEAM or q.have >= q.need
end

-- Whether a player of team may toggle a ready-up of kind: a team's player
-- their team's, an MvM defender their own.
function MayToggle(kind, team, defenders)
	if kind == PLAYER then return team == defenders end
	return team == Teams.RED or team == Teams.BLUE
end
