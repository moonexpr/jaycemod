-- Why this player is not spawning (WS.SpawnMessage, ws/sh_spawn_manager.lua)
-- as cooler-hud's spectator panel shows it (resource/ui/spectator.res, no
-- top or bottom bar): the ReinforcementsLabel at the bottom left
-- (ws.tf_hud's RespawnLabel), its text centred in
-- HudFontMediumSmallSecondary (TF2 Secondary) and the scheme's label colour
-- (TanLight), in TFThinLineBorder. On every map and in every mode, so a
-- lock shows in Sandbox mode too. Over the rest of the HUD (WS.HUD's OVERLAY
-- band), as TF2's spectator panel is. Above the label, while the player
-- waits for a wave, what moved their respawn
-- (games.gameplay.respawn_modifiers): a line for each reason, its seconds green
-- when sooner and red when later, and whether a limit cut the total.
local M = WS.require("games.gameplay.respawn_modifiers")
local S = WS.require("games.system.spawn_manager")
local Hud = WS.require("ws.tf_hud")

-- TF2's 480-tall units.
local REASON_TALL, REASON_GAP = 10, 2
local TAN_LIGHT = Color(235, 226, 202)
local SOONER, LATER = Color(153, 204, 102), Color(224, 96, 96)
local FONT, REASON_FONT = "WS.SpawnMessage", "WS.SpawnReason"

local fontFor
local told = { modifiers = {}, total = 0, limited = false } -- this player's last death's

WS.Events.Listen("game_respawn_modifiers", "ws_spawn_manager", function(fields)
	told = fields
end)

-- A line centred on centre, its top at y: its seconds in their colour, then its words.
local function Reason(seconds, words, centre, y)
	local text = M.Seconds(seconds)
	surface.SetFont(REASON_FONT)
	local secondsW = surface.GetTextSize(text .. "  ")
	local w = secondsW + surface.GetTextSize(words)
	local x = centre - w / 2
	draw.SimpleTextOutlined(text, REASON_FONT, x, y, seconds < 0 and SOONER or LATER, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
	draw.SimpleTextOutlined(words, REASON_FONT, x + secondsW, y, TAN_LIGHT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
end

-- The reasons stacked upward from the label's top, the last nearest it.
local function DrawReasons(ply, label, unit)
	if ply:Alive() or ply:GetNW2Int("ws_spawn_status", S.NONE) ~= S.WAVE or #told.modifiers == 0 then return end
	local lines = {}
	for _, m in ipairs(told.modifiers) do lines[#lines + 1] = { m.seconds, M.Describe(m) } end
	if told.limited then lines[#lines + 1] = { told.total, "in all (the most a respawn moves)" } end
	local centre, step = label.x + label.w / 2, (REASON_TALL + REASON_GAP) * unit
	local y = label.y - #lines * step
	for _, line in ipairs(lines) do
		Reason(line[1], line[2], centre, y)
		y = y + step
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
		surface.CreateFont(REASON_FONT, { font = Hud.FONT_SECONDARY, size = math.Round(REASON_TALL * unit), weight = 500, antialias = true })
		fontFor = unit
	end
	local label = Hud.RespawnLabel(h, unit)
	WS.TFHud.DrawBorder(Hud.RESPAWN_BORDER, label, unit, Hud.RESPAWN_SRC_CORNER, Hud.RESPAWN_DRAW_CORNER)
	draw.SimpleText(text, FONT, label.x + label.w / 2, label.y + label.h / 2, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	DrawReasons(ply, label, unit)
end)
