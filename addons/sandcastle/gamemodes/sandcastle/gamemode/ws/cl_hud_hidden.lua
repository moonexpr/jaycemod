-- The player's HUD switches (WS.HUD, made in ws/sh_core.lua and drawn by
-- GM:HUDPaint): cl_hud_hidden names the paths not to draw, each with
-- everything under it (game.match.team_scores; player), saved between
-- sessions; cl_hud_print lists every element in drawing order and whether
-- it is hidden, by the player or the code.
local DrawList = list.drawlist

local hidden = CreateClientConVar("cl_hud_hidden", "", true, false,
	"HUD elements not to draw, by path, each with everything under it (spaces between; cl_hud_print lists them)")

local function Apply()
	WS.HUD:SetHidden(DrawList.ParseNames(hidden:GetString()))
end

Apply()
cvars.AddChangeCallback("cl_hud_hidden", Apply, "ws_hud")

concommand.Add("cl_hud_print", function()
	for _, entry in ipairs(WS.HUD:Entries()) do
		print(string.format("%-16s %4d  %s", entry.name, entry.order, entry.hidden and "hidden" or "shown"))
	end
end, nil, "List the HUD's elements in drawing order, and which cl_hud_hidden hides")
