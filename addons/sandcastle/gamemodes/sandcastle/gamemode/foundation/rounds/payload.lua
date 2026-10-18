-- The payload mode (TF_GAMETYPE_ESCORT): a team_train_watcher chooses it,
-- as CTFGameRules::Activate does, over control points and under KOTH. It
-- plays no special cap lines, and on a race map (tf_logic_multiple_escort) each side hears its
-- stage outcome when the round is won.
local Rounds = require("foundation.rounds")
local Race = require("foundation.payload.race")
module(...)

Mode = Rounds.Mode:Extend("payload")
-- The points (or the cart) decide its rounds: no round limits.
Mode.OBJECTIVE = true
Mode.PRIORITY = 2
Mode.HUD = Rounds.HUD_PAYLOAD

-- CTeamTrainWatcherMaster::FireGameEvent("teamplay_round_win"), on a race only.
function Mode:RoundWinLines(winner, fullRound, race)
	if not race then return {} end
	return Race.OutcomeLines(winner, fullRound)
end
