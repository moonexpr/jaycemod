-- The bomb defusal mode of games.gameplay.rounds, as CS:S's de_ maps play it.
-- The round is fought in STALEMATE as arena's is, nobody respawning, under
-- CS:S's gamerules (cs_gamerules). RED's bomb is an item_teamflag its own
-- team carries (MvM's bomb, RED the invaders). The bomb's state
-- (features.defuse.model), which the defuse controller tells the rounds
-- (SetObjectiveState { bomb }), decides how the round may end: before the
-- plant as arena, BLU winning when the timer runs out (TARGET_SAVED); after
-- it neither the timer nor RED's death ends the round, which the bomb
-- decides, and only RED wins by killing the other side.
local Rounds = gameplay.rounds
local Teams = gameplay.teams
local State = require("games.gameplay.rounds.state")
module(...)

Mode = Rounds.Mode:Extend("defuse")
-- Over every other mode a map can carry.
Mode.PRIORITY = 4
Mode.OBJECTIVE = true
Mode.RULES_CLASS = "cs_gamerules"
Mode.CREATES_TIME_LIMIT_TIMER = false
Mode.ROUND_STATE = State.STALEMATE
Mode.STALEMATE_IS_ROUND = true
Mode.AUTO_SCRAMBLE = false
Mode.FLAG_OWNERS_CARRY = true
Mode.FLAG_INVADERS = Teams.RED

-- A game begins with at least MIN_PLAYERS players and NPCs, on either team.
MIN_PLAYERS = 2
Mode.PLAYERS_NEEDED = { count = MIN_PLAYERS }

-- The freeze before the round, in seconds (CS:S's mp_freezetime).
FREEZE_SECONDS = 5

function Mode:MayWinByPoints(team, q) return false end

function Mode:SetupSeconds(settings) return FREEZE_SECONDS end

-- settings.defuseRoundTime: the round's length in seconds (cs_defuse_logic's).
function Mode:StalemateSeconds(settings) return settings.defuseRoundTime or 0 end

local function Bomb(world) return world.objectiveState and world.objectiveState.bomb end

function Mode:StalemateTimerWin(world) return Teams.BLUE, Rounds.WINREASON.TARGET_SAVED end

function Mode:HoldsStalemateTimer(world)
	local bomb = Bomb(world)
	return bomb ~= nil and not bomb:EliminationWins(nil)
end

function Mode:EliminationWins(team, world)
	local bomb = Bomb(world)
	return bomb == nil or bomb:EliminationWins(team)
end
