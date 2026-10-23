-- Why this player is not spawning (WS.SpawnMessage, ws/sh_spawn_manager.lua)
-- as cooler-hud's spectator panel shows it (resource/ui/spectator.res, no
-- top or bottom bar): the ReinforcementsLabel at the bottom left
-- (ws.tf_hud's RespawnLabel), its text centred in
-- HudFontMediumSmallSecondary (TF2 Secondary) and the scheme's label colour
-- (TanLight), in TFThinLineBorder. On every map and in every mode, so a
-- lock shows in Sandbox mode too. Over the rest of the HUD (WS.HUD's OVERLAY
-- band), as TF2's spectator panel is. Under the label, while the player
-- waits for a wave, what moved their respawn
-- (games.gameplay.respawn_modifiers) in a panel of its own (ws.tf_hud's
-- RespawnReasons): a line for each reason, its seconds green when sooner
-- and red when later, and whether a limit cut the total.
local M = gameplay.respawn_modifiers
local S = system.spawn_manager
local Hud = WS.require("ws.tf_hud")

local TAN_LIGHT = Color(235, 226, 202)
local SOONER, LATER = Color(153, 204, 102), Color(224, 96, 96)
local FONT, REASON_FONT = "WS.SpawnMessage", "WS.SpawnReason"

local fontFor
local told = { modifiers = {}, total = 0, limited = false } -- this player's last death's

WS.Events.Listen("game_respawn_modifiers", "ws_spawn_manager", function(fields)
	told = fields
end)

-- The reasons' panel under the label, a line a reason: its seconds in
-- their colour, right-aligned in their column, then its words.
local function DrawReasons(ply, h, unit)
	if ply:Alive() or ply:GetNW2Int("ws_spawn_status", S.NONE) ~= S.WAVE or #told.modifiers == 0 then return end
	local lines = {}
	for _, m in ipairs(told.modifiers) do lines[#lines + 1] = { m.seconds, M.Describe(m) } end
	if told.limited then lines[#lines + 1] = { told.total, "in all (the most a respawn moves)" } end
	local layout = Hud.RespawnReasons(h, unit, #lines)
	WS.TFHud.DrawPanel(Hud.REASONS_PANEL, layout.panel, unit)
	for i, line in ipairs(lines) do
		local at = layout.lines[i]
		draw.SimpleText(M.Seconds(line[1]), REASON_FONT, at.seconds.x, at.seconds.y, line[1] < 0 and SOONER or LATER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		draw.SimpleText(line[2], REASON_FONT, at.words.x, at.words.y, TAN_LIGHT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

WS.HUD:Add("player.spawn_message", WS.HUD_ORDER.OVERLAY, function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local text = WS.SpawnMessage(ply, CurTime())
	if not text then return end
	local h = ScrH()
	local unit = Hud.Unit(h)
	if fontFor ~= unit then
		surface.CreateFont(FONT, { font = Hud.FONT_SECONDARY, size = math.Round(Hud.RESPAWN_FONT_TALL * unit), weight = 500, antialias = true })
		surface.CreateFont(REASON_FONT, { font = Hud.FONT_SECONDARY, size = math.Round(Hud.REASON_TALL * unit), weight = 500, antialias = true })
		fontFor = unit
	end
	local label = Hud.RespawnLabel(h, unit)
	WS.TFHud.DrawBorder(Hud.RESPAWN_BORDER, label, unit, Hud.RESPAWN_SRC_CORNER, Hud.RESPAWN_DRAW_CORNER)
	draw.SimpleText(text, FONT, label.x + label.w / 2, label.y + label.h / 2, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	DrawReasons(ply, h, unit)
end)
