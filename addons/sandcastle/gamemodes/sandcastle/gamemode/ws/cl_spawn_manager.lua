-- Why this player is not spawning (WS.SpawnMessage, ws/sh_spawn_manager.lua),
-- as TF2's spectator panel says it ("Respawn in: 5 seconds", "No respawning
-- in Arena Mode"), low in the middle of the screen, on every map and in
-- every mode, so a lock shows in Sandbox mode too.
local FONT, FONT_TALL, Y = "WS.SpawnMessage", 14, 0.7

local fontFor

hook.Add("HUDPaint", "ws_spawn_manager", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local text = WS.SpawnMessage(ply, CurTime())
	if not text then return end
	local w, h = ScrW(), ScrH()
	if fontFor ~= h then
		surface.CreateFont(FONT, { font = "TF2 Secondary", size = math.Round(FONT_TALL * h / 480), weight = 500 })
		fontFor = h
	end
	draw.SimpleTextOutlined(text, FONT, w / 2, h * Y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
end)
