-- An in-memory objective port for Round tests: what the capture controller
-- answers about the map's control point master (games.gameplay.rounds'
-- OBJECTIVE_METHODS). rounds_modes_test checks it implements every method.
local setmetatable = setmetatable

local Fake = {}

local Objective = {}
Objective.__index = Objective

-- o = { playingMiniRounds, numPlayable, playAllRounds, remaining = { [team] = n },
-- scorePerRound }; unset fields are a map without mini-rounds that scores per round.
function Fake.Objective(o)
	o = o or {}
	return setmetatable({
		playingMiniRounds = o.playingMiniRounds == true,
		numPlayable = o.numPlayable or 0,
		playAllRounds = o.playAllRounds == true,
		remaining = o.remaining or {},
		scorePerRound = o.scorePerRound ~= false,
		suddenDeathWins = {},
	}, Objective)
end

function Objective:PlayingMiniRounds() return self.playingMiniRounds end
function Objective:NumPlayable() return self.numPlayable end
function Objective:PlayAllRounds() return self.playAllRounds end
function Objective:RoundsRemaining(team) return self.remaining[team] or 0 end
function Objective:ScorePerRound() return self.scorePerRound end

-- The master's SetWinnerAndForceCaps, recorded.
function Objective:SuddenDeathWin(team)
	self.suddenDeathWins[#self.suddenDeathWins + 1] = team
end

return Fake
