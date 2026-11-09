-- Control points: the round's points and who holds them.
local GAME = {}

function GAME:Applies()
	return game_manager.Enabled("game_control_points")
end

function GAME:Standing(objective)
	local points = {}
	for _, entry in ipairs(WS.Feature("capture"):HudPoints()) do
		points[#points + 1] = { owner = entry.hud.owner, inRound = entry.hud.inRound, hidden = entry.hud.hidden }
	end
	objective.points = points
end

function GAME:CreatePanel()
	local view = WS.Feature("capture")
	return self:ObjectivePanel(function(w, h)
		if WS.Active() and not WS.HUD:IsHidden("game.objective.points") then view.Draw(w, h) end
	end)
end

game_manager.RegisterClass("game_control_points", GAME, "game_default")
