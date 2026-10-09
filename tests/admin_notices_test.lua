-- foundation.admin_notices: what each side hears and sees when an admin
-- changes the game from the editors, as TF2 tells a scramble: an announcer
-- line and a notification card with an icon.
local T = dofile("tests/harness.lua")
local Notices = T.require("foundation.admin_notices")

local NOBODY, RED, BLU = 0, 2, 3

local function For(notices, audience)
	for _, n in ipairs(notices) do
		if n.audience == audience then return n end
	end
end

T.test("a retracted cart tells its attackers they were rolled back and the defenders they gained", function()
	local notices = Notices.CartRetracted(BLU, RED)
	T.eq(#notices, 2)
	local attackers, defenders = For(notices, BLU), For(notices, RED)
	T.eq(attackers.text, "The Administrator has rolled your cart back!")
	T.eq(attackers.sound, "Announcer.TimeAddedForEnemy")
	T.eq(attackers.team, BLU, "in the attackers' colour")
	T.eq(defenders.text, "The Administrator has pushed back your enemy's team progress!")
	T.eq(defenders.sound, "Announcer.TimeAwardedCongrats")
	T.eq(attackers.icon, Notices.ICON_ADMIN)
end)

T.test("an advanced cart is the retract the other way round", function()
	local notices = Notices.CartAdvanced(BLU, RED)
	T.eq(For(notices, BLU).text, "The Administrator has pushed your cart forward!")
	T.eq(For(notices, BLU).sound, "Announcer.TimeAwardedCongrats")
	T.eq(For(notices, RED).text, "The Administrator has pushed your enemy's cart forward!")
	T.eq(For(notices, RED).sound, "Announcer.TimeAddedForEnemy")
end)

-- Neither good nor bad for a side: everyone hears the system alert and the
-- announcer's security alert, and sees the card.
local function Neutral(notice, text, icon)
	T.eq(notice.text, text)
	T.eq(notice.audience, NOBODY, "everyone")
	T.eq(notice.team, NOBODY, "in no team's colour")
	T.eq(notice.sound, Notices.NEUTRAL_LINE, "the announcer's security alert")
	T.eq(notice.chime, Notices.NEUTRAL_CHIME, "the system alert")
	if icon then T.eq(notice.icon, icon) end
end

T.test("respawn waves changed, for either team or both, are one notice: the respawn times were modified", function()
	local notices = Notices.RespawnTimesModified()
	T.eq(#notices, 1)
	Neutral(notices[1], "The Administrator has modified the respawn times.", Notices.ICON_CLOCK)
	T.eq(Notices.NEUTRAL_CHIME, "ui/system_message_alert.wav")
	T.eq(Notices.NEUTRAL_LINE, "Announcer.SecurityAlert")
end)

T.test("respawns switched off or on, the map's waves restored, and the timer paused or resumed are neutral", function()
	Neutral(Notices.RespawnsDisabled(true)[1], "The Administrator has disabled respawns.", Notices.ICON_STOPPED)
	Neutral(Notices.RespawnsDisabled(false)[1], "The Administrator has enabled respawns again.")
	Neutral(Notices.MapRespawnWaves()[1], "The Administrator has restored the map's respawn waves.")
	Neutral(Notices.TimerPaused(true)[1], "The Administrator has paused the round timer.", Notices.ICON_STOPPED)
	Neutral(Notices.TimerPaused(false)[1], "The Administrator has resumed the round timer.")
end)

T.test("the cart's notices are good or bad for a side, with no system alert", function()
	for _, n in ipairs(Notices.CartRetracted(BLU, RED)) do T.eq(n.chime, nil) end
end)

-- The security alert is for the first neutral notice in a while: within
-- NEUTRAL_LINE_GAP of the last one, only the system alert chimes.
T.test("a neutral notice soon after another keeps its chime but drops the announcer's alert", function()
	local first, lastAt = Notices.Spoken(Notices.TimerPaused(true), nil, 100)
	T.eq(first[1].sound, Notices.NEUTRAL_LINE, "the first speaks")
	T.eq(lastAt, 100)
	local soon, soonAt = Notices.Spoken(Notices.TimerPaused(false), lastAt, 100 + Notices.NEUTRAL_LINE_GAP - 1)
	T.eq(soon[1].sound, nil, "too soon: no alert")
	T.eq(soon[1].chime, Notices.NEUTRAL_CHIME, "but the chime")
	T.eq(soonAt, 100, "the gap still runs from the last alert")
	local later = Notices.Spoken(Notices.TimerPaused(true), soonAt, 100 + Notices.NEUTRAL_LINE_GAP)
	T.eq(later[1].sound, Notices.NEUTRAL_LINE, "a while later it speaks again")
	local cart = Notices.Spoken(Notices.CartRetracted(BLU, RED), 100, 101)
	T.eq(cart[1].sound, "Announcer.TimeAddedForEnemy", "a side's line always plays")
end)

-- The AI war, told as visitors from another universe arriving and leaving.
T.test("the AI war's start and end are neutral notices of visitors from another universe", function()
	Neutral(Notices.WarStarted()[1], "Visitors from another universe have arrived!", Notices.ICON_VISITORS)
	Neutral(Notices.WarEnded()[1], "The visitors have returned to their own universe.", Notices.ICON_VISITORS)
	T.eq(type(Notices.ICON_VISITORS), "string")
end)

-- A point awarded from the Game Rules editor: everyone hears a bell and
-- sees the card in the team's colour.
T.test("points awarded to a team ring a bell and tell everyone, in the team's colour", function()
	local names = { [RED] = "RED", [BLU] = "BLU" }
	local one = Notices.PointsAwarded(RED, 1, names)
	T.eq(#one, 1)
	T.eq(one[1].text, "The Administrator has awarded RED a point!")
	T.eq(one[1].audience, NOBODY, "everyone")
	T.eq(one[1].team, RED)
	T.eq(one[1].chime, Notices.BELL)
	T.eq(one[1].sound, nil, "no announcer line")
	T.eq(Notices.PointsAwarded(BLU, 3, names)[1].text, "The Administrator has awarded BLU 3 points!")
	T.eq(Notices.BELL, "Hud.EndRoundScored", "TF2's chime as a team scores")
end)

T.finish()
