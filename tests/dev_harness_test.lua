-- The dev workbench's gamerules harness model (addons/sandcastle_dev,
-- sandcastle_dev_harness): what becomes of each input the map sends the
-- gamerules, and the trace of everything it saw.
local T = dofile("tests/harness.lua")
local Harness = T.require("sandcastle_dev_harness")

local function Input(name, value)
	return {
		name = name,
		value = value or "",
		caller = "logic_auto",
	}
end

T.test("a new harness forwards every input", function()
	local h = Harness.New(16)
	T.eq(h:Mode(), Harness.FORWARD, "forwarding")
	T.eq(h:Input(Input("SetRedTeamRole", "1"), 0), Harness.FORWARD, "forwarded")
end)

T.test("intercepting drops every input, queueing holds them for release in order", function()
	local h = Harness.New(16)
	h:SetMode(Harness.INTERCEPT)
	T.eq(h:Input(Input("PlayVO"), 0), Harness.INTERCEPT, "dropped")
	h:SetMode(Harness.QUEUE)
	T.eq(h:Input(Input("SetRedTeamRespawnWaveTime", "9"), 1), Harness.QUEUE, "queued")
	T.eq(h:Input(Input("SetBlueTeamRespawnWaveTime", "3"), 2), Harness.QUEUE, "queued")
	local released = h:TakeQueued()
	T.eq(#released, 2, "both released")
	T.eq(released[1].name, "SetRedTeamRespawnWaveTime", "in order")
	T.eq(#h:TakeQueued(), 0, "once")
end)

T.test("a rule for one input overrides the mode, whatever the input's case", function()
	local h = Harness.New(16)
	h:SetRule("setredteamrespawnwavetime", Harness.INTERCEPT)
	T.eq(h:Input(Input("SetRedTeamRespawnWaveTime", "9"), 0), Harness.INTERCEPT, "ruled")
	T.eq(h:Input(Input("SetBlueTeamRespawnWaveTime", "3"), 0), Harness.FORWARD, "the rest forwards")
	h:SetRule("SetRedTeamRespawnWaveTime", nil)
	T.eq(h:Input(Input("setredteamrespawnwavetime", "9"), 0), Harness.FORWARD, "rule cleared")
end)

T.test("an unknown mode or action is refused with the known ones", function()
	local h = Harness.New(16)
	local ok, err = pcall(h.SetMode, h, "pause")
	T.eq(ok, false, "refused")
	T.eq(tostring(err):find(Harness.INTERCEPT, 1, true) ~= nil, true, "lists the modes: " .. tostring(err))
	T.eq((pcall(h.SetRule, h, "PlayVO", "eat")), false, "an unknown rule action is refused")
end)

T.test("the trace numbers every entry, and Since returns only newer ones", function()
	local h = Harness.New(16)
	h:Input(Input("SetRedTeamRole", "1"), 5)
	h:Record("output", { name = "OnWonByTeam1" }, 6)
	local all = h:Since(0)
	T.eq(#all, 2, "two entries")
	T.eq(all[1].kind, "input", "the input")
	T.eq(all[1].action, Harness.FORWARD, "with what became of it")
	T.eq(all[1].at, 5, "and when")
	T.eq(all[2].name, "OnWonByTeam1", "the output's fields")
	T.eq(#h:Since(all[1].seq), 1, "only the newer")
	T.eq(h:LastSeq(), all[2].seq, "the last sequence number")
end)

T.test("a recorded field may not overwrite the entry's own seq, kind or at", function()
	local h = Harness.New(16)
	for _, key in ipairs({ "seq", "kind", "at" }) do
		local ok, err = pcall(h.Record, h, "effect", { [key] = "mine" }, 0)
		T.eq(ok, false, key .. " refused")
		T.eq(tostring(err):find(key, 1, true) ~= nil, true, "names " .. key .. ": " .. tostring(err))
	end
end)

T.test("Of keeps the entries of the kinds asked for, in order", function()
	local h = Harness.New(16)
	h:Record("output", { name = "a" }, 0)
	h:Record("effect", { effect = "cleanup" }, 0)
	h:Record("output", { name = "b" }, 0)
	local outputs = Harness.Of(h:Since(0), { "output" })
	T.eq(#outputs, 2, "two outputs")
	T.eq(outputs[2].name, "b", "in order")
end)

T.test("the trace keeps only the newest entries, and says how many it dropped", function()
	local h = Harness.New(3)
	for i = 1, 5 do h:Record("note", { i = i }, i) end
	local kept = h:Since(0)
	T.eq(#kept, 3, "capacity kept")
	T.eq(kept[1].i, 3, "the oldest kept")
	T.eq(h:Dropped(), 2, "two dropped")
end)

T.finish()
