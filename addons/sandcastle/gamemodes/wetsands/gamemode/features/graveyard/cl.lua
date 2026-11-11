-- The graveyard feature's view: each team's players left alive, the counter
-- graveyard.nut keeps on arenaplayercounter.res.
local FONT = "Sandcastle.Graveyard.Counter"
local FONT_SIZE = 32
local FOOT, GAP = 64, 40
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE

local View = {}

surface.CreateFont (FONT, { font = "TF2 Build", size = FONT_SIZE, weight = 500, antialias = true })

function View:DrawCount (team, x, y)
	draw.SimpleTextOutlined (GetGlobal2Int ("ws_graveyard_alive_" .. team, 0), FONT, x, y, WS.TeamColor [team],
		TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
end

WS.HUD:Add ("game.objective.graveyard", WS.HUD_ORDER.OBJECTIVES, function (w, h)
	if not WS.TeamPlay () then return end
	View:DrawCount (RED, w / 2 - GAP, h - FOOT)
	View:DrawCount (BLUE, w / 2 + GAP, h - FOOT)
end)

return View
