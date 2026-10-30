-- The hostages' voice (features.hostage.voice): TF2 Classic's Civilian
-- (Benjamoose's lines, sound/vo/civilian_benjamoose/), a line for each thing
-- that happens to a hostage, picked by a number the caller draws.
local T = dofile("tests/harness.lua")
local Voice = T.require("features.hostage.voice")

local EVENTS = { Voice.TAKEN, Voice.FOLLOWING, Voice.LEFT, Voice.CALLING, Voice.RESCUED }

T.test("every event has lines, each a .wav of the civilian's under vo/, lower case", function()
	for _, event in ipairs(EVENTS) do
		local lines = Voice.Lines(event)
		T.eq(#lines > 0, true, event .. " has lines")
		for _, path in ipairs(lines) do
			T.eq(path:match("^vo/civilian_benjamoose/civ_[%l_]+%(%d+%)%.wav$") ~= nil, true, path)
		end
	end
end)

T.test("taken, a hostage thanks its rescuer or urges it on; rescued, it is glad", function()
	local taken = table.concat(Voice.Lines(Voice.TAKEN), " ")
	T.eq(taken:find("civ_thanks(1)", 1, true) ~= nil, true, "thanks")
	T.eq(taken:find("civ_go_go_go(1)", 1, true) ~= nil, true, "go go go")
	T.eq(Voice.Lines(Voice.RESCUED)[1]:find("civ_success", 1, true) ~= nil, true, "success")
	T.eq(Voice.Lines(Voice.LEFT)[1]:find("civ_calling_for_help", 1, true) ~= nil, true, "left behind, it calls for help")
end)

T.test("a line is picked by the number drawn, wrapping past the last", function()
	local lines = Voice.Lines(Voice.RESCUED)
	T.eq(Voice.Pick(Voice.RESCUED, 1), lines[1], "the first")
	T.eq(Voice.Pick(Voice.RESCUED, #lines), lines[#lines], "the last")
	T.eq(Voice.Pick(Voice.RESCUED, #lines + 1), lines[1], "wraps")
end)

T.test("an unknown event is the caller's mistake", function()
	T.eq(pcall(Voice.Lines, "nonsense"), false, "refused")
end)

T.test("every line any event says is listed once, for clients to fetch", function()
	local all, seen = Voice.All(), {}
	for _, path in ipairs(all) do
		T.eq(seen[path], nil, path .. " once")
		seen[path] = true
	end
	for _, event in ipairs(EVENTS) do
		for _, path in ipairs(Voice.Lines(event)) do T.eq(seen[path], true, path .. " listed") end
	end
end)

T.test("a hostage speaks at most once in SPEAK_GAP seconds", function()
	T.defined(Voice.SPEAK_GAP, "SPEAK_GAP")
	T.eq(Voice.MaySpeak(nil, 10), true, "never spoke")
	T.eq(Voice.MaySpeak(10, 10 + Voice.SPEAK_GAP - 0.1), false, "too soon")
	T.eq(Voice.MaySpeak(10, 10 + Voice.SPEAK_GAP), true, "after the gap")
end)

T.finish()
