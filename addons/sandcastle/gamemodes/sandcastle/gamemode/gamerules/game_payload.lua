-- Payload: a team pushes a cart along the track.
local GAME = {}

function GAME:Applies()
	return game_manager.Enabled("game_payload")
end

-- Each team's furthest active cart.
function GAME:Standing(objective)
	local carts = {}
	for _, watcher in ipairs(WS.Feature("payload").watchers) do
		if IsValid(watcher) and watcher:IsActive() then
			local hud = watcher:HudState()
			carts[hud.team] = math.max(carts[hud.team] or 0, hud.progress)
		end
	end
	if next(carts) then objective.carts = carts end
end

function GAME:CreatePanel()
	local view = WS.Feature("payload")
	return self:ObjectivePanel(function(w, h)
		if WS.Active() and not WS.HUD:IsHidden("game.objective.carts") then view.Draw(w, h) end
	end)
end

game_manager.RegisterClass("game_payload", GAME, "game_default")
