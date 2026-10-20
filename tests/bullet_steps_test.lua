local T = dofile("tests/harness.lua")
local Steps = T.require("foundation.combat.bullet_steps")

local function Recorder(log, name, answer)
	return function(shooter, data)
		log[#log + 1] = name
		data[name] = shooter
		return answer
	end
end

T.test("steps run in their order, whatever order they were added in", function()
	local steps, log = Steps.New(), {}
	steps:Add("late", 30, Recorder(log, "late"))
	steps:Add("early", 10, Recorder(log, "early"))
	steps:Add("middle", 20, Recorder(log, "middle"))
	steps:Run("me", {})
	T.eq(table.concat(log, " "), "early middle late", "the order")
end)

T.test("a shot any step changed is fired changed, and every step still sees it", function()
	local steps, log = Steps.New(), {}
	steps:Add("changes", 10, Recorder(log, "changes", Steps.CHANGED))
	steps:Add("listens", 20, Recorder(log, "listens"))
	local data = {}
	T.eq(steps:Run("me", data), Steps.CHANGED, "changed")
	T.eq(data.listens, "me", "the later step saw it")
end)

T.test("a step that suppresses the shot stops it there", function()
	local steps, log = Steps.New(), {}
	steps:Add("changes", 10, Recorder(log, "changes", Steps.CHANGED))
	steps:Add("suppresses", 20, Recorder(log, "suppresses", Steps.SUPPRESSED))
	steps:Add("after", 30, Recorder(log, "after"))
	T.eq(steps:Run("me", {}), Steps.SUPPRESSED, "suppressed")
	T.eq(table.concat(log, " "), "changes suppresses", "the later step never ran")
end)

T.test("a shot no step changed is left to the engine", function()
	local steps = Steps.New()
	steps:Add("listens", 10, function() end)
	T.eq(steps:Run("me", {}), nil, "untouched")
end)

T.test("adding a step under a name it has replaces it", function()
	local steps, log = Steps.New(), {}
	steps:Add("step", 10, Recorder(log, "old"))
	steps:Add("step", 10, Recorder(log, "new"))
	steps:Run("me", {})
	T.eq(table.concat(log, " "), "new", "only the new one")
end)

T.finish()
