-- The hostage rescue mode of games.gameplay.rounds, as CS:S's hostage maps
-- play it. The round is fought in STALEMATE as arena's is: nobody respawns,
-- and a team wins by killing the other (RED, who keeps the hostages) or by
-- leading the hostages out (BLU: features.hostage.model's Outcome, which the
-- hostage controller turns into HOSTAGES_RESCUED). Timed (mp_hostage_roundtime)
-- it ends, when the timer runs out, in RED's win: the hostages were not
-- rescued. Untimed it ends with one of the other two.
local Rounds = gameplay.rounds
local Teams = gameplay.teams
local State = require("games.gameplay.rounds.state")
module(...)

Mode = Rounds.Mode:Extend("hostage")
-- Over every other mode a map can carry.
Mode.PRIORITY = 4
-- The hostages decide the round, so no round limit does.
Mode.OBJECTIVE = true
-- CS:S's gamerules (the cs_gamerules entity), not TF2's.
Mode.RULES_CLASS = "cs_gamerules"
-- CTeamplayRoundBasedRules::CreateTimeLimitTimer returns in arena.
Mode.CREATES_TIME_LIMIT_TIMER = false
-- State_Think_PREROUND goes to STALEMATE, as arena's does.
Mode.ROUND_STATE = State.STALEMATE
Mode.STALEMATE_IS_ROUND = true
Mode.AUTO_SCRAMBLE = false

-- A game begins with at least MIN_PLAYERS players and NPCs, on either team.
MIN_PLAYERS = 2
Mode.PLAYERS_NEEDED = { count = MIN_PLAYERS }

-- The freeze before the round, in seconds (CS:S's mp_freezetime).
FREEZE_SECONDS = 5

function Mode:MayWinByPoints(team, q) return false end

function Mode:SetupSeconds(settings) return FREEZE_SECONDS end

-- settings.hostageRoundTime: the round's length in seconds, 0 for untimed.
-- It is the round's timer, shown as the arena's is.
function Mode:StalemateSeconds(settings) return settings.hostageRoundTime or 0 end

-- RED keeps the hostages until the timer runs out.
function Mode:StalemateTimerWin(world)
	return Teams.RED, Rounds.WINREASON.HOSTAGES_NOT_RESCUED
end
