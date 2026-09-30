-- What the round HUD says: the win panel (CTFWinPanel::FireGameEvent), the
-- sudden death panel (CHudStalemate::SetupStalematePanel), the time-added
-- flash, and TF2's localization tokens read from tf_english.txt (UTF-16LE).
-- English strings from tf_english.txt.
local math, string, table = math, string, table
local Rounds = require("foundation.rounds")
local Teams = require("foundation.teams")
module(...)

local RED, BLUE = Teams.RED, Teams.BLUE
local FIRST_GAME_TEAM = Teams.FIRST_GAME_TEAM
local WINREASON, STALEMATE = Rounds.WINREASON, Rounds.STALEMATE
local SECONDS_PER_MINUTE = 60

local TEAM_LABEL = {
	[RED] = "RED",
	[BLUE] = "BLU",
}
local REASON_TEXT = {
	[WINREASON.ALL_POINTS_CAPTURED] = "%s captured all control points",
	[WINREASON.OPPONENTS_DEAD] = "%s killed all opponents during sudden death",
	[WINREASON.DEFEND_UNTIL_TIME_LIMIT] = "%s successfully defended until time ran out",
	[WINREASON.STALEMATE] = "You're all losers",
	[WINREASON.TIMELIMIT] = "%s had more points when the time limit was reached",
	[WINREASON.WINLIMIT] = "%s had more points when the win limit was reached",
	[WINREASON.WINDIFFLIMIT] = "%s was ahead by the required difference to win",
}

-- info = { winner, reason, fullRound, remaining (areas left for the winner) }
function WinPanel(info)
	if info.winner < FIRST_GAME_TEAM then
		return {
			title = "STALEMATE",
			reason = REASON_TEXT[WINREASON.STALEMATE],
		}
	end
	local team = TEAM_LABEL[info.winner]
	local areaDefense = info.reason == WINREASON.DEFEND_UNTIL_TIME_LIMIT and not info.fullRound
	local title
	if info.fullRound then
		title = team .. " TEAM WINS!"
	elseif areaDefense then
		title = team .. " TEAM DEFENDS!"
	else
		title = team .. " TEAM SEIZES AREA"
	end
	local text = REASON_TEXT[info.reason]
	local panel = {
		title = title,
		reason = text and string.format(text, team) or nil,
	}
	if not info.fullRound and info.reason ~= WINREASON.STALEMATE then
		panel.details = info.remaining .. (info.remaining == 1 and " more area to win" or " more areas to win")
	end
	return panel
end

local STALEMATE_REASON = {
	[STALEMATE.JOIN_MID] = "Sit back and relax while you wait for this petty conflict to end.",
	[STALEMATE.TIMER] = "You've run out of time. Watch your back and finish 'em off. No more spawning.",
	[STALEMATE.SERVER_TIMELIMIT] = "Map time limit reached. No more spawning, so make this count.",
}

function StalematePanel(reason)
	return {
		title = "SUDDEN DEATH!",
		reason = STALEMATE_REASON[reason],
	}
end

-- The flash beside the timer when time is added (teamplay_timer_time_added).
function TimeAdded(seconds)
	local sign = seconds < 0 and "-" or "+"
	local s = math.abs(seconds)
	return string.format("%s%d:%02d", sign, math.floor(s / SECONDS_PER_MINUTE), s % SECONDS_PER_MINUTE)
end

-- Localization ---------------------------------------------------------------------

local TAB, NEWLINE, SPACE, QUOTE = 9, 10, 32, 34
local BOM = 0xFEFF
local HIGH_SURROGATE, LOW_SURROGATE = 0xD800, 0xDC00

local function Utf16(s)
	return (string.gsub(s, ".", function(c) return c .. "\0" end))
end

local function Utf8(code)
	if code < 0x80 then return string.char(code) end
	if code < 0x800 then
		return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
	end
	if code < 0x10000 then
		return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
	end
	return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
		0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local function Unit(raw, i)
	return string.byte(raw, i) + string.byte(raw, i + 1) * 256
end

-- Only indentation between the line's start (or the file's BOM) and unit i.
local function StartsLine(raw, i)
	i = i - 2
	while i >= 1 do
		local u = Unit(raw, i)
		if u == NEWLINE or u == BOM then return true end
		if u ~= TAB and u ~= SPACE then return false end
		i = i - 2
	end
	return true
end

-- The English text of a "#Token" from a UTF-16LE localization file (as
-- tf/resource/tf_english.txt), matched case-insensitively. Text without a
-- leading "#" is returned as it is; an unknown token is nil.
function Localize(raw, token)
	if string.sub(token, 1, 1) ~= "#" then return token end
	local key = Utf16('"' .. string.lower(string.sub(token, 2)) .. '"')
	local lowered = string.lower(raw)
	local init = 1
	local i
	-- A key starts its line (after any indent); the same text after a key is a value.
	repeat
		local s, e = string.find(lowered, key, init, true)
		if not s then return nil end
		if s % 2 == 1 and StartsLine(raw, s) then i = e + 1 end
		init = e + 1
	until i
	while i < #raw and (Unit(raw, i) == TAB or Unit(raw, i) == SPACE) do i = i + 2 end
	if Unit(raw, i) ~= QUOTE then return nil end
	i = i + 2
	local out = {}
	while i < #raw do
		local u = Unit(raw, i)
		if u == QUOTE then return table.concat(out) end
		if u >= HIGH_SURROGATE and u < LOW_SURROGATE then
			local low = Unit(raw, i + 2)
			out[#out + 1] = Utf8(0x10000 + (u - HIGH_SURROGATE) * 0x400 + (low - LOW_SURROGATE))
			i = i + 4
		else
			out[#out + 1] = Utf8(u)
			i = i + 2
		end
	end
	return nil
end
