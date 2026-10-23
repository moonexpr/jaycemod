-- Payload race (plr_ maps, marked by tf_logic_multiple_escort). The SDK's
-- CTeamTrainWatcherMaster (team_train_watcher.cpp) is compiled out and its
-- think is empty: what it defines is the PLR_* announcer lines and, on a
-- round win, the stage-outcome line each side hears. The carts are compared
-- as CTFGameRules does it (PlayTrainCaptureAlert, Helltower lines): by each
-- watcher's distance along its track.
local pairs, string = pairs, string
local Teams = gameplay.teams
module(...)

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE

-- distances = { [team] = distance along track }; the team ahead, or nobody when level.
function Leader(distances)
	local red, blu = distances[RED] or 0, distances[BLU] or 0
	if red > blu then return RED end
	if blu > red then return BLU end
	return NOBODY
end

-- CTeamTrainWatcherMaster::FireGameEvent("teamplay_round_win"): winner and
-- loser each hear their line; full_round picks the final-stage pair.
function OutcomeLines(winner, fullRound)
	if winner ~= RED and winner ~= BLU then return {} end
	local loser = winner == RED and BLU or RED
	local stage = fullRound and "Final" or "First"
	return {
		[winner] = "Announcer.PLR_" .. stage .. "StageOutcome01",
		[loser] = "Announcer.PLR_" .. stage .. "StageOutcome02",
	}
end

-- The TWM_* names the SDK precaches. TF2's soundscripts no longer define
-- them, but the recordings ship in tf2_sound_vo_english; name -> wave.
local LINES = {
	FirstStageOutcome = 2,
	RaceGeneral = 15,
	SecondStageOutcome = 4,
	FinalStageOutcome = 2,
	FinalStageStart = 9,
}

function Sounds()
	local sounds = {}
	for stem, count in pairs(LINES) do
		for n = 1, count do
			local suffix = string.format("%02d", n)
			sounds["Announcer.PLR_" .. stem .. suffix] = "vo/announcer_plr_" .. string.lower(stem) .. suffix .. ".mp3"
		end
	end
	return sounds
end
