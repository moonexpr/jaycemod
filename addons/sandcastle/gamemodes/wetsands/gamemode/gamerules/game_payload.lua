-- Payload: a team pushes a cart along the track.
local GAME = {}

function GAME:Applies()
	return WS.FeatureLoaded("payload")
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

game_manager.RegisterClass("game_payload", GAME, "game_default")
