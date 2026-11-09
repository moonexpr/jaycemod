-- Capture the flag.
local GAME = {}

function GAME:Applies()
	return WS.FeatureLoaded("flag")
end

-- The flags each team has captured, and the limit.
function GAME:Standing(objective)
	local flag = WS.Feature("flag")
	objective.captures = {
		[WS.TEAM_RED] = flag.tally:Captures(WS.TEAM_RED),
		[WS.TEAM_BLUE] = flag.tally:Captures(WS.TEAM_BLUE),
	}
	objective.caplimit = flag:CapLimit()
end

game_manager.RegisterClass("game_ctf", GAME, "game_default")
