-- features.hostage.announcer: the announcer's lines for the hostages, TF2
-- Classified's VIP lines (its game_sounds_vo_tf2c.txt, TF2's own files):
-- BLU, the rescuers, hear them as "our VIP"'s team, RED as the other side's,
-- as a hostage is taken, let go, rescued or killed.
local T = dofile("tests/harness.lua")
local Announcer = T.require("features.hostage.announcer")
local Rescue = T.require("features.hostage.model")
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE

T.test("each change of a hostage's state is an event, or none", function()
	T.eq(Announcer.Event(Rescue.HELD, Rescue.FOLLOWING), Announcer.TAKEN, "taken")
	T.eq(Announcer.Event(Rescue.FOLLOWING, Rescue.HELD), Announcer.LET_GO, "let go")
	T.eq(Announcer.Event(Rescue.FOLLOWING, Rescue.RESCUED), Announcer.RESCUED, "rescued")
	T.eq(Announcer.Event(Rescue.HELD, Rescue.KILLED), Announcer.KILLED, "killed held")
	T.eq(Announcer.Event(Rescue.FOLLOWING, Rescue.KILLED), Announcer.KILLED, "killed following")
	T.eq(Announcer.Event(Rescue.HELD, Rescue.HELD), nil, "no change")
end)

T.test("each side hears its own line of each event, one of the VIP mode's", function()
	for _, event in ipairs({ Announcer.TAKEN, Announcer.LET_GO, Announcer.RESCUED, Announcer.KILLED }) do
		for _, team in ipairs({ RED, BLUE }) do
			local lines = Announcer.Lines(event, team)
			T.eq(#lines > 0, true, event .. " has lines for " .. team)
			for _, path in ipairs(lines) do T.eq(path:match("^vo/.+%.mp3$") ~= nil, true, path .. " a voice file") end
		end
		T.eq(Announcer.Lines(event, RED)[1] ~= Announcer.Lines(event, BLUE)[1], true, event .. ": the sides hear different lines")
	end
end)

T.test("BLU's taking is TF2 Classified's VIP_OurTeamHasFlag, RED's its VIP_TheirTeamHasFlag", function()
	T.eq(Announcer.Lines(Announcer.TAKEN, BLUE)[1], "vo/announcer_sd_possession02.mp3", "ours")
	T.eq(Announcer.Lines(Announcer.TAKEN, RED)[1], "vo/announcer_sd_possession05.mp3", "theirs")
end)

T.test("every line is listed once, for the server to precache", function()
	local all, seen = Announcer.All(), {}
	for _, path in ipairs(all) do seen[path] = (seen[path] or 0) + 1 end
	for _, event in ipairs({ Announcer.TAKEN, Announcer.LET_GO, Announcer.RESCUED, Announcer.KILLED }) do
		for _, team in ipairs({ RED, BLUE }) do
			for _, path in ipairs(Announcer.Lines(event, team)) do T.eq(seen[path], 1, path) end
		end
	end
end)

T.test("a line is drawn by the random source given", function()
	local lines = Announcer.Lines(Announcer.TAKEN, BLUE)
	T.eq(Announcer.Pick(Announcer.TAKEN, BLUE, function(low, high) return high end), lines[#lines], "the last")
end)

T.finish()
