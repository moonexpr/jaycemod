-- Control points: the round's points and who holds them.
local GAME = {}

function GAME:Applies()
	return WS.FeatureLoaded("capture")
end

function GAME:Standing(objective)
	local points = {}
	for _, entry in ipairs(WS.Feature("capture"):HudPoints()) do
		points[#points + 1] = { owner = entry.hud.owner, inRound = entry.hud.inRound, hidden = entry.hud.hidden }
	end
	objective.points = points
end

game_manager.RegisterClass("game_control_points", GAME, "game_default")
