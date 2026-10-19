-- Why this player is not spawning (WS.SpawnMessage, ws/sh_spawn_manager.lua)
-- as TF2's spectator panel shows it (resource/ui/spectator.res): its top
-- bar, black and translucent across the screen (CSpectatorGUI's
-- BLACK_BAR_COLOR), and on it the ReinforcementsLabel, centred, in
-- HudFontMediumSmallSecondary (TF2 Secondary) and the scheme's label colour
-- (TanLight). On every map and in every mode, so a lock shows in Sandbox
-- mode too. Over the rest of the HUD (PostDrawHUD, after GM:HUDPaint's
-- round panels), as TF2's spectator panel is.
-- TF2's 480-tall units.
local BAR_TALL, LABEL_Y, LABEL_TALL, FONT_TALL = 84, 50, 18, 18
local BAR_COLOR = Color(0, 0, 0, 196)
local TAN_LIGHT = Color(235, 226, 202)
local FONT = "WS.SpawnMessage"

local fontFor

hook.Add("PostDrawHUD", "ws_spawn_manager", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local text = WS.SpawnMessage(ply, CurTime())
	if not text then return end
	local w, h = ScrW(), ScrH()
	local unit = h / 480
	if fontFor ~= unit then
		surface.CreateFont(FONT, { font = "TF2 Secondary", size = math.Round(FONT_TALL * unit), weight = 500, antialias = true })
		fontFor = unit
	end
	cam.Start2D()
	surface.SetDrawColor(BAR_COLOR)
	surface.DrawRect(0, 0, w, BAR_TALL * unit)
	draw.SimpleText(text, FONT, w / 2, (LABEL_Y + LABEL_TALL / 2) * unit, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	cam.End2D()
end)
