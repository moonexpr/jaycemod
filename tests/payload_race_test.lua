-- foundation.payload.race: payload race (plr_) comparisons.
local T = dofile("tests/harness.lua")
local R = T.require("foundation.payload.race")

local Teams = T.require("games.gameplay.teams")

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE

T.test("the leader is the cart farther along its track", function()
	T.eq(R.Leader({ [RED] = 900, [BLU] = 400 }), RED)
	T.eq(R.Leader({ [RED] = 100, [BLU] = 400 }), BLU)
	T.eq(R.Leader({ [RED] = 400, [BLU] = 400 }), NOBODY)
end)

T.test("a missing cart counts as not started", function()
	T.eq(R.Leader({ [BLU] = 10 }), BLU)
	T.eq(R.Leader({}), NOBODY)
end)

T.test("a stage win plays the first-stage outcome lines", function()
	local lines = R.OutcomeLines(RED, false)
	T.eq(lines[RED], "Announcer.PLR_FirstStageOutcome01")
	T.eq(lines[BLU], "Announcer.PLR_FirstStageOutcome02")
end)

T.test("the full-round win plays the final-stage outcome lines", function()
	local lines = R.OutcomeLines(BLU, true)
	T.eq(lines[BLU], "Announcer.PLR_FinalStageOutcome01")
	T.eq(lines[RED], "Announcer.PLR_FinalStageOutcome02")
end)

T.test("a stalemate plays no outcome lines", function()
	T.eq(next(R.OutcomeLines(NOBODY, true)), nil)
end)

T.test("every announcer line the SDK names maps to its mp3", function()
	local sounds = R.Sounds()
	T.eq(sounds["Announcer.PLR_RaceGeneral15"], "vo/announcer_plr_racegeneral15.mp3")
	T.eq(sounds["Announcer.PLR_FinalStageStart09"], "vo/announcer_plr_finalstagestart09.mp3")
	local n = 0
	for _ in pairs(sounds) do n = n + 1 end
	T.eq(n, 32)
end)

T.finish()
