-- The hostage rescue mode of games.gameplay.rounds, as CS:S's hostage maps
-- play it. The round is fought in STALEMATE as arena's is: nobody respawns,
-- and a team wins by killing the other (RED, who keeps the hostages) or by
-- leading the hostages out (BLU: features.hostage.model's Outcome, which the
-- hostage controller turns into HOSTAGES_RESCUED). It has no timer: it ends
-- with one of the two.
local Rounds = gameplay.rounds
local State = require("games.gameplay.rounds.state")
module(...)

Mode = Rounds.Mode:Extend("hostage")
-- Over every other mode a map can carry.
Mode.PRIORITY = 4
-- The hostages decide the round, so no round limit does.
Mode.OBJECTIVE = true
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

-- Untimed.
function Mode:StalemateSeconds(settings) return 0 end
