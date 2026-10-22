-- Why this player is not spawning (WS.SpawnMessage, ws/sh_spawn_manager.lua)
-- as TF2's spectator panel shows it (resource/ui/spectator.res): its top
-- bar, black and translucent across the screen (CSpectatorGUI's
-- BLACK_BAR_COLOR), and on it the ReinforcementsLabel, centred, in
-- HudFontMediumSmallSecondary (TF2 Secondary) and the scheme's label colour
-- (TanLight). On every map and in every mode, so a lock shows in Sandbox
-- mode too. Over the rest of the HUD (WS.HUD's OVERLAY band), as TF2's
-- spectator panel is. Under the bar, while the player waits for a wave,
-- what moved their respawn (foundation.respawn_modifiers): a line for each
-- reason, its seconds green when sooner and red when later, and whether a
-- limit cut the total.
local M = WS.require("foundation.respawn_modifiers")
local S = WS.require("foundation.spawn_manager")

-- TF2's 480-tall units.
local BAR_TALL, LABEL_Y, LABEL_TALL, FONT_TALL = 84, 50, 18, 18
local REASON_TALL, REASON_GAP = 10, 2
local BAR_COLOR = Color(0, 0, 0, 196)
local TAN_LIGHT = Color(235, 226, 202)
local SOONER, LATER = Color(153, 204, 102), Color(224, 96, 96)
local FONT, REASON_FONT = "WS.SpawnMessage", "WS.SpawnReason"

local fontFor
local told = { modifiers = {}, total = 0, limited = false } -- this player's last death's

WS.Events.Listen("game_respawn_modifiers", "ws_spawn_manager", function(fields)
	told = fields
end)

-- A line under the bar: its seconds in their colour, then its words.
local function Reason(seconds, words, y)
	local text = M.Seconds(seconds)
	surface.SetFont(REASON_FONT)
	local secondsW = surface.GetTextSize(text .. "  ")
	local w = secondsW + surface.GetTextSize(words)
	local x = (ScrW() - w) / 2
	draw.SimpleTextOutlined(text, REASON_FONT, x, y, seconds < 0 and SOONER or LATER, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
	draw.SimpleTextOutlined(words, REASON_FONT, x + secondsW, y, TAN_LIGHT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
end

local function DrawReasons(ply, unit)
	if ply:Alive() or ply:GetNW2Int("ws_spawn_status", S.NONE) ~= S.WAVE or #told.modifiers == 0 then return end
	local y = (BAR_TALL + REASON_GAP) * unit
	for _, m in ipairs(told.modifiers) do
		Reason(m.seconds, M.Describe(m), y)
		y = y + (REASON_TALL + REASON_GAP) * unit
	end
	if told.limited then Reason(told.total, "in all (the most a respawn moves)", y) end
end

WS.HUD:Add("player.spawn_message", WS.HUD_ORDER.OVERLAY, function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local text = WS.SpawnMessage(ply, CurTime())
	if not text then return end
	local w, h = ScrW(), ScrH()
	local unit = h / 480
	if fontFor ~= unit then
		surface.CreateFont(FONT, { font = "TF2 Secondary", size = math.Round(FONT_TALL * unit), weight = 500, antialias = true })
		surface.CreateFont(REASON_FONT, { font = "TF2 Secondary", size = math.Round(REASON_TALL * unit), weight = 500, antialias = true })
		fontFor = unit
	end
	surface.SetDrawColor(BAR_COLOR)
	surface.DrawRect(0, 0, w, BAR_TALL * unit)
	draw.SimpleText(text, FONT, w / 2, (LABEL_Y + LABEL_TALL / 2) * unit, TAN_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	DrawReasons(ply, unit)
end)
