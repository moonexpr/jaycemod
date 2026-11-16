-- game_control_points: what the game asks of a map's control points.
local T = dofile ("tests/harness.lua")

ROUND_WAITING, ROUND_PREPARE, ROUND_ACTIVE, ROUND_OVER = 0, 1, 2, 3
SERVER = true
local state, answer
GAMEMODE = { GetRoundState = function () return state end }
hook = { Run = function (name) if name == "ControlPointRules" then return answer end end }
dofile ("addons/sandcastle/gamemodes/sandcastle/gamemode/gamerules/game_control_points.lua")
local Game = game_manager.GetClass ("game_control_points")

local function Rules ()
	local rules = Game:GetRules ()
	return rules.PointsMayBeCaptured, rules.PointsUnlock
end

T.test ("points are captured and unlock but while a round is being prepared or is over", function ()
	answer = nil
	for _, case in ipairs (
		{
			{ ROUND_WAITING, true, "no round on" },
			{ ROUND_PREPARE, false, "preparing" },
			{ ROUND_ACTIVE, true, "a round on" },
			{ ROUND_OVER, false, "over" }
		}
	) do
		state = case [1]
		local mayBeCaptured, unlock = Rules ()
		T.eq (mayBeCaptured, case [2], case [3] .. ": captured")
		T.eq (unlock,        case [2], case [3] .. ": unlocking")
	end
end)

T.test ("a mode's answer is the game's", function ()
	state = ROUND_ACTIVE
	answer = { mayBeCaptured = false, unlock = true }
	local mayBeCaptured, unlock = Rules ()
	T.eq (mayBeCaptured, false, "the mode's captures")
	T.eq (unlock,        true,  "the mode's unlocks")
end)

T.finish ()
