-- The control points mode (TF_GAMETYPE_CP): symmetric CP and attack/defend
-- alike, since TF2 has one rule set for both and tells them apart only by the
-- map's data (a master's restrict_team_cap_win, rounds, setup timers). A
-- team_control_point_master chooses it. The koth mode extends it.
local ipairs = ipairs
local Rounds = gameplay.rounds
local Teams = gameplay.teams
module(...)

SUCCESS = "Announcer.Success"
FAILURE = "Announcer.Failure"

local GAME_TEAMS = { Teams.RED, Teams.BLUE }

Mode = Rounds.Mode:Extend("control_points")
-- The points (or the cart) decide its rounds: no round limits.
Mode.OBJECTIVE = true
Mode.PRIORITY = 1
Mode.HUD = Rounds.HUD_CONTROL_POINTS

-- CTFGameRules::PlaySpecialCapSounds: with score_style 0, a cap that does
-- not win the game plays Success to the cappers and Failure to every other
-- game team, from FIRST_GAME_TEAM up.
function Mode:CapSounds(capTeam, q)
	local lines = {}
	if not q.scorePerRound or q.wouldWinGame then return lines end
	for _, team in ipairs(GAME_TEAMS) do
		lines[#lines + 1] = {
			team = team,
			sound = team == capTeam and SUCCESS or FAILURE,
		}
	end
	return lines
end
