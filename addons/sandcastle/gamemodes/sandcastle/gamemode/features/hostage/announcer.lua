-- The announcer's lines for the hostages: TF2 Classified's one-sided VIP
-- lines (scripts/game_sounds_vo_tf2c.txt's Announcer.VIP_*, which are TF2's
-- own voice files, mounted already), the escorted VIP's: not VIP Race's,
-- whose VIPs race for control points to the control points' lines and the
-- Civilian's own (Civilian.VIPR_*). The rescuers, BLU, hear the "our team"
-- line of each event, RED the "their team" one: a hostage taken
-- (VIP_*TeamHasFlag), let go when its rescuer dies (VIP_*TeamDroppedFlag),
-- rescued (VIP_*TeamCapped) or killed (VIP_OurVIPDeath for BLU, VIP_VIPDeath
-- for RED).
local ipairs, pairs, require = ipairs, pairs, require
local Teams = gameplay.teams
local Rescue = require("features.hostage.model")
module(...)

TAKEN, LET_GO, RESCUED, KILLED = "taken", "let_go", "rescued", "killed"

local RED, BLUE = Teams.RED, Teams.BLUE

local LINES = {
	[TAKEN] = {
		[BLUE] = { "vo/announcer_sd_possession02.mp3", "vo/announcer_sd_possession17.mp3", "vo/announcer_sd_possession23.mp3" },
		[RED] = { "vo/announcer_sd_possession05.mp3", "vo/announcer_sd_possession09.mp3", "vo/announcer_sd_possession15.mp3" },
	},
	[LET_GO] = {
		[BLUE] = { "vo/announcer_sd_possession26.mp3", "vo/announcer_sd_possession27.mp3" },
		[RED] = { "vo/announcer_sd_possession11.mp3", "vo/announcer_sd_possession20.mp3" },
	},
	[RESCUED] = {
		[BLUE] = { "vo/announcer_sd_generic_success_fail02.mp3", "vo/announcer_sd_generic_success_fail03.mp3" },
		[RED] = { "vo/announcer_sd_generic_success_fail05.mp3" },
	},
	[KILLED] = {
		[BLUE] = { "vo/announcer_sd_monkeynaut_end_crash01.mp3", "vo/announcer_sd_monkeynaut_end_crash02.mp3",
			"vo/announcer_sd_monkeynaut_end_crash03.mp3" },
		[RED] = { "vo/announcer_am_killstreak01.mp3", "vo/announcer_am_killstreak06.mp3", "vo/announcer_dec_kill06.mp3",
			"vo/announcer_dec_kill07.mp3", "vo/announcer_dec_kill08.mp3" },
	},
}

local EVENTS = {
	[Rescue.HELD .. ">" .. Rescue.FOLLOWING] = TAKEN,
	[Rescue.FOLLOWING .. ">" .. Rescue.HELD] = LET_GO,
	[Rescue.FOLLOWING .. ">" .. Rescue.RESCUED] = RESCUED,
	[Rescue.HELD .. ">" .. Rescue.KILLED] = KILLED,
	[Rescue.FOLLOWING .. ">" .. Rescue.KILLED] = KILLED,
}

-- The event a hostage's change from before to after is, or nil.
function Event(before, after) return EVENTS[before .. ">" .. after] end

-- The lines team hears of event (paths under sound/).
function Lines(event, team) return LINES[event][team] end

-- One of them, drawn by randomInt(low, high).
function Pick(event, team, randomInt)
	local lines = Lines(event, team)
	return lines[randomInt(1, #lines)]
end

-- Every line, for the server to precache.
function All()
	local all = {}
	for _, sides in pairs(LINES) do
		for _, lines in pairs(sides) do
			for _, path in ipairs(lines) do all[#all + 1] = path end
		end
	end
	return all
end
