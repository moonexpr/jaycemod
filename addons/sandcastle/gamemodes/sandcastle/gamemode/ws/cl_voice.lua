-- Who is talking, in WS.UI's TF2 look in place of GMod's voice panels
-- (base's VoiceNotify, which PlayerStartVoice no longer makes): a stack of
-- boxes up the screen's right edge, one per talker, newest at the bottom,
-- each its team's colour along its left edge, the name in TF2 Secondary,
-- and a light tan bar to the loudness of the voice.
local UI = WS.UI
local THEME = UI.THEME

-- TF2's 480-tall units: the box, the gap between boxes, its team edge, its
-- level bar, and how far up from the bottom the stack ends (above the HUD).
local WIDE, TALL, GAP, EDGE, BAR_TALL, PAD = 120, 20, 3, 3, 2, 5
local BOTTOM = 120
local NAME_TALL = 10
local NAME_FONT = "WS.Voice.Name"
local NEUTRAL = Color(160, 150, 135)

local talkers = {} -- in the order they started

local fontFor

local function Font(unit)
	if fontFor == unit then return end
	surface.CreateFont(NAME_FONT, { font = "TF2 Secondary", size = math.Round(NAME_TALL * unit), weight = 500 })
	fontFor = unit
end

local function Remove(ply)
	for i = #talkers, 1, -1 do
		if talkers[i] == ply then table.remove(talkers, i) end
	end
end

-- Returning a value keeps the base gamemode from making its own panel.
hook.Add("PlayerStartVoice", "ws_voice", function(ply)
	Remove(ply)
	talkers[#talkers + 1] = ply
	return true
end)

hook.Add("PlayerEndVoice", "ws_voice", function(ply)
	Remove(ply)
	return true
end)

WS.HUD:Add("game.notices.voice", WS.HUD_ORDER.NOTICES, function(w, h)
	for i = #talkers, 1, -1 do
		if not IsValid(talkers[i]) then table.remove(talkers, i) end
	end
	if #talkers == 0 then return end
	local unit = h / 480
	Font(unit)
	local bw, bh, gap = WIDE * unit, TALL * unit, GAP * unit
	local x = w - bw - PAD * unit
	for i = #talkers, 1, -1 do
		local ply = talkers[i]
		local y = h - BOTTOM * unit - (#talkers - i + 1) * (bh + gap)
		UI.Box(bw, bh, x, y)
		local b = THEME.borderWidth
		draw.RoundedBoxEx(THEME.corner, x + b, y + b, EDGE * unit, bh - b * 2, WS.TeamColor[ply:Team()] or NEUTRAL,
			true, false, true, false)
		local pad = PAD * unit + EDGE * unit
		draw.SimpleText(ply:Nick(), NAME_FONT, x + pad, y + bh / 2 - BAR_TALL * unit / 2, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local barW = (bw - pad - PAD * unit) * math.Clamp(ply:VoiceVolume(), 0, 1)
		surface.SetDrawColor(THEME.border)
		surface.DrawRect(x + pad, y + bh - b - BAR_TALL * unit - unit, barW, BAR_TALL * unit)
	end
end, WS.Active)
