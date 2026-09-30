-- foundation.rounds.text: the win panel's wording (CTFWinPanel::FireGameEvent) and the
-- lookup of TF2 localization tokens in tf_english.txt (UTF-16LE).
local T = dofile("tests/harness.lua")
local R = T.require("foundation.rounds")
local Text = T.require("foundation.rounds.text")

local W = R.WINREASON
local Teams = T.require("foundation.teams")
local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE

local function Panel(winner, reason, fullRound, remaining)
	return Text.WinPanel({
		winner = winner,
		reason = reason,
		fullRound = fullRound,
		remaining = remaining,
	})
end

T.test("a full round win says the team wins", function()
	local p = Panel(BLU, W.ALL_POINTS_CAPTURED, true, 0)
	T.eq(p.title, "BLU TEAM WINS!")
	T.eq(p.reason, "BLU captured all control points")
	T.eq(p.details, nil)
end)

T.test("a mini-round win seizes the area and counts what is left", function()
	local p = Panel(BLU, W.ALL_POINTS_CAPTURED, false, 2)
	T.eq(p.title, "BLU TEAM SEIZES AREA")
	T.eq(p.details, "2 more areas to win")
	p = Panel(BLU, W.ALL_POINTS_CAPTURED, false, 1)
	T.eq(p.details, "1 more area to win")
end)

T.test("defending a mini-round until time runs out defends", function()
	local p = Panel(RED, W.DEFEND_UNTIL_TIME_LIMIT, false, 1)
	T.eq(p.title, "RED TEAM DEFENDS!")
	T.eq(p.reason, "RED successfully defended until time ran out")
end)

T.test("a stalemate has everyone lose", function()
	local p = Panel(NOBODY, W.STALEMATE, true, 0)
	T.eq(p.title, "STALEMATE")
	T.eq(p.reason, "You're all losers")
end)

T.test("sudden death wins by killing everyone", function()
	local p = Panel(RED, W.OPPONENTS_DEAD, true, 0)
	T.eq(p.reason, "RED killed all opponents during sudden death")
end)

T.test("sudden death explains why it started", function()
	local p = Text.StalematePanel(R.STALEMATE.TIMER)
	T.eq(p.title, "SUDDEN DEATH!")
	T.eq(p.reason, "You've run out of time. Watch your back and finish 'em off. No more spawning.")
	T.eq(Text.StalematePanel(R.STALEMATE.SERVER_TIMELIMIT).reason, "Map time limit reached. No more spawning, so make this count.")
end)

local function Utf16(s)
	return (string.gsub(s, ".", function(c) return c .. "\0" end))
end

local FILE = "\255\254" .. Utf16('"lang"\r\n{\r\n"Tokens"\r\n{\r\n'
	.. '"[english]Goldrush_blue_setup_goal"\t"old"\r\n'
	.. '"Goldrush_blue_setup_goal"\t\t"Move the cart!"\r\n'
	.. '"Other"\t"x"\r\n}\r\n}\r\n')

T.test("a token's text is read from the UTF-16 file", function()
	T.eq(Text.Localize(FILE, "#Goldrush_blue_setup_goal"), "Move the cart!")
end)

T.test("token lookup ignores case, as VGUI's does", function()
	T.eq(Text.Localize(FILE, "#goldrush_BLUE_setup_goal"), "Move the cart!")
end)

T.test("an unknown token is not found", function()
	T.eq(Text.Localize(FILE, "#Missing"), nil)
end)

T.test("plain text needs no lookup", function()
	T.eq(Text.Localize(FILE, "Push the cart"), "Push the cart")
end)

T.test("non-ASCII characters decode to UTF-8", function()
	local raw = "\255\254" .. Utf16('"K"\t"') .. "\233\0" .. Utf16('"\r\n')
	T.eq(Text.Localize(raw, "#K"), "\195\169")
end)

T.test("time added reads as the flash beside the timer shows it", function()
	T.eq(Text.TimeAdded(180), "+3:00", "three minutes")
	T.eq(Text.TimeAdded(45), "+0:45", "seconds")
	T.eq(Text.TimeAdded(-30), "-0:30", "taken away")
end)

T.finish()
