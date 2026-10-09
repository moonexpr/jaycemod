-- What each side hears and sees when an admin changes the game from the
-- editors, as TF2 tells a scramble: an announcer line (sound, on
-- CHAN_VOICE2), a chime (on CHAN_AUTO, under it; nil for none) and a
-- notification card (text, in team's colour, with icon) to audience (a
-- team; UNASSIGNED is everyone). A change good for one side and bad for the
-- other gives each its line; a neutral one (NEUTRAL_LINE and NEUTRAL_CHIME)
-- goes to everyone. Each function returns the list of { audience, team,
-- text, icon, sound, chime }.
local format, ipairs = string.format, ipairs
local Teams = require("foundation.teams")
module(...)

local EVERYONE = Teams.UNASSIGNED

ICON_ADMIN = "hud/ico_teambalance" -- the scales: the Administrator stepped in
ICON_CLOCK = "hud/ico_time_10"
ICON_STOPPED = "hud/ico_time_none"
ICON_RESUMED = "hud/ico_time_60"
ICON_VISITORS = "hud/ico_teamswitch" -- the AI war's soldiers come and go

local GOOD, BAD = "Announcer.TimeAwardedCongrats", "Announcer.TimeAddedForEnemy"
NEUTRAL_LINE = "Announcer.SecurityAlert"
NEUTRAL_CHIME = "ui/system_message_alert.wav"
NEUTRAL_LINE_GAP = 30 * 60 -- the security alert speaks once in this long
BELL = "Hud.EndRoundScored" -- a point awarded: TF2's chime as a team scores (ui/scored.wav)

local function Notice(audience, team, text, icon, sound, chime)
	return { audience = audience, team = team, text = text, icon = icon, sound = sound, chime = chime }
end

local function Neutral(text, icon)
	return { Notice(EVERYONE, EVERYONE, text, icon, NEUTRAL_LINE, NEUTRAL_CHIME) }
end

-- The Game Rules editor's retract: the attackers lose ground, the
-- defenders gain it.
function CartRetracted(attackers, defenders)
	return {
		Notice(attackers, attackers, "The Administrator has rolled your cart back!", ICON_ADMIN, BAD),
		Notice(defenders, defenders, "The Administrator has pushed back your enemy's team progress!", ICON_ADMIN, GOOD),
	}
end

function CartAdvanced(attackers, defenders)
	return {
		Notice(attackers, attackers, "The Administrator has pushed your cart forward!", ICON_ADMIN, GOOD),
		Notice(defenders, defenders, "The Administrator has pushed your enemy's cart forward!", ICON_ADMIN, BAD),
	}
end

-- Either team's respawn wave, or both, set: one notice, once the admin has
-- left the fields alone (the editors' controller waits).
function RespawnTimesModified()
	return Neutral("The Administrator has modified the respawn times.", ICON_CLOCK)
end

function RespawnsDisabled(disabled)
	if disabled then return Neutral("The Administrator has disabled respawns.", ICON_STOPPED) end
	return Neutral("The Administrator has enabled respawns again.", ICON_CLOCK)
end

function MapRespawnWaves()
	return Neutral("The Administrator has restored the map's respawn waves.", ICON_CLOCK)
end

-- Points awarded to team from the Game Rules editor (once the score field
-- has rested): a bell, and the card in the team's colour, to everyone.
-- names: team -> name.
function PointsAwarded(team, points, names)
	local text = points == 1 and format("The Administrator has awarded %s a point!", names[team])
		or format("The Administrator has awarded %s %d points!", names[team], points)
	return { Notice(EVERYONE, team, text, ICON_ADMIN, nil, BELL) }
end

-- The AI war, told as visitors from another universe arriving and leaving.
function WarStarted()
	return Neutral("Visitors from another universe have arrived!", ICON_VISITORS)
end

function WarEnded()
	return Neutral("The visitors have returned to their own universe.", ICON_VISITORS)
end

function TimerPaused(paused)
	if paused then return Neutral("The Administrator has paused the round timer.", ICON_STOPPED) end
	return Neutral("The Administrator has resumed the round timer.", ICON_RESUMED)
end

-- The notices as played at now: a neutral notice keeps its chime always,
-- its announcer alert only when none has spoken for NEUTRAL_LINE_GAP since
-- lastAt (nil: never). Returns them and when the alert last spoke.
function Spoken(notices, lastAt, now)
	local played = {}
	for i, n in ipairs(notices) do
		local copy = Notice(n.audience, n.team, n.text, n.icon, n.sound, n.chime)
		if copy.sound == NEUTRAL_LINE then
			if lastAt and now - lastAt < NEUTRAL_LINE_GAP then
				copy.sound = nil
			else
				lastAt = now
			end
		end
		played[i] = copy
	end
	return played, lastAt
end
