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

-- The announcer as a talker: a soundscape on its channel (CHAN_VOICE2, the
-- announcer's soundscripts: WS.PlaySoundscape) shows ANNOUNCER, newest, until
-- the line ends; a new line, which cuts the last off, starts it again. A
-- script picks one of its files as it plays, so the note lasts the longest;
-- at least ANNOUNCER_LEAST, as an .mp3's length may read 0. Its bar beats
-- at ANNOUNCER_BEAT, there being no voice level to read.
local ANNOUNCER = "Administrator"
local ANNOUNCER_LEAST, ANNOUNCER_BEAT = 1, 10
local announcerUntil = 0

hook.Add("WSSoundscapePlayed", "ws_voice", function(name)
	local script = sound.GetProperties(name)
	if not script or script.channel ~= CHAN_VOICE2 then return end
	local files = isstring(script.sound) and { script.sound } or script.sound
	local longest = ANNOUNCER_LEAST
	for _, path in ipairs(files) do longest = math.max(longest, SoundDuration(path)) end
	announcerUntil = CurTime() + longest
end)

-- The boxes to draw, oldest first: { name, color, level }.
local function Notes()
	local notes = {}
	for i = #talkers, 1, -1 do
		if not IsValid(talkers[i]) then table.remove(talkers, i) end
	end
	for _, ply in ipairs(talkers) do
		notes[#notes + 1] = { name = ply:Nick(), color = WS.TeamColor[ply:Team()] or NEUTRAL, level = ply:VoiceVolume() }
	end
	local now = CurTime()
	if now < announcerUntil then
		notes[#notes + 1] = { name = ANNOUNCER, color = NEUTRAL, level = math.abs(math.sin(now * ANNOUNCER_BEAT)) }
	end
	return notes
end

WS.HUD:Add("game.notices.voice", WS.HUD_ORDER.NOTICES, function(w, h)
	local notes = Notes()
	if #notes == 0 then return end
	local unit = h / 480
	Font(unit)
	local bw, bh, gap = WIDE * unit, TALL * unit, GAP * unit
	local x = w - bw - PAD * unit
	for i = #notes, 1, -1 do
		local note = notes[i]
		local y = h - BOTTOM * unit - (#notes - i + 1) * (bh + gap)
		UI.Box(bw, bh, x, y)
		local b = THEME.borderWidth
		draw.RoundedBoxEx(THEME.corner, x + b, y + b, EDGE * unit, bh - b * 2, note.color, true, false, true, false)
		local pad = PAD * unit + EDGE * unit
		draw.SimpleText(note.name, NAME_FONT, x + pad, y + bh / 2 - BAR_TALL * unit / 2, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local barW = (bw - pad - PAD * unit) * math.Clamp(note.level, 0, 1)
		surface.SetDrawColor(THEME.border)
		surface.DrawRect(x + pad, y + bh - b - BAR_TALL * unit - unit, barW, BAR_TALL * unit)
	end
end, WS.Active)
