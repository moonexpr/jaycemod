-- games.gameplay.respawn_modifiers: what a player did since their last spawn
-- moves their respawn sooner or later, each reason told on the respawn
-- screen; the total never cuts into the death animation.
local T = dofile("tests/harness.lua")
local M = T.require("games.gameplay.respawn_modifiers")
local Credit = T.require("games.gameplay.kill_credit")

local NOTHING = { kills = 0, captures = 0, defenses = 0, finishedOff = false, suicide = false }

local function Facts(over)
	local facts = {}
	for k, v in pairs(NOTHING) do facts[k] = v end
	for k, v in pairs(over or {}) do facts[k] = v end
	return facts
end

local function Find(list, reason)
	for _, m in ipairs(list) do
		if m.reason == reason then return m end
	end
end

T.test("the tuning is defined", function()
	T.defined(M.KILL_SECONDS, "KILL_SECONDS")
	T.defined(M.MOST_KILLS, "MOST_KILLS")
	T.defined(M.CAPTURE_SECONDS, "CAPTURE_SECONDS")
	T.defined(M.DEFENSE_SECONDS, "DEFENSE_SECONDS")
	T.defined(M.SUICIDE_SECONDS, "SUICIDE_SECONDS")
	T.defined(M.MOST_PENALTY, "MOST_PENALTY")
end)

T.test("a life with nothing to tell moves nothing", function()
	T.eq(#M.For(Facts()), 0, "no reasons")
	T.eq(M.Total({}, 10), 0, "no change")
end)

T.test("kills bring the respawn sooner, each, up to MOST_KILLS", function()
	local two = Find(M.For(Facts({ kills = 2 })), M.KILLS)
	T.eq(two.count, 2, "two kills")
	T.eq(two.seconds, -2 * M.KILL_SECONDS, "a kill's seconds each")
	local many = Find(M.For(Facts({ kills = M.MOST_KILLS + 4 })), M.KILLS)
	T.eq(many.count, M.MOST_KILLS + 4, "every kill told")
	T.eq(many.seconds, -M.MOST_KILLS * M.KILL_SECONDS, "but only MOST_KILLS count")
end)

T.test("objectives and an enemy's finishing blow bring it sooner; a suicide later", function()
	local list = M.For(Facts({ captures = 1, defenses = 2, finishedOff = true, suicide = true }))
	T.eq(Find(list, M.CAPTURE).seconds, -M.CAPTURE_SECONDS, "a capture")
	T.eq(Find(list, M.DEFENSE).seconds, -2 * M.DEFENSE_SECONDS, "two defenses")
	T.eq(Find(list, M.FINISHED_OFF).seconds, Credit.CREDITED_RESPAWN, "finished off: kill credit's")
	T.eq(Find(list, M.SUICIDE).seconds, M.SUICIDE_SECONDS, "a suicide, later")
end)

T.test("reasons come in a fixed order: sooner first, then later", function()
	local list = M.For(Facts({ kills = 1, captures = 1, defenses = 1, finishedOff = true, suicide = true }))
	local order = {}
	for i, m in ipairs(list) do order[i] = m.reason end
	T.eq(table.concat(order, ","), table.concat({ M.KILLS, M.CAPTURE, M.DEFENSE, M.FINISHED_OFF, M.SUICIDE }, ","))
end)

-- The total moves when the wait counts from: sooner by at most the team's
-- wave (the death animation stays), later by at most MOST_PENALTY.
T.test("the total is the sum, at most a wave sooner and MOST_PENALTY later", function()
	local wave = 10
	local list = { { seconds = -2 }, { seconds = 5 } }
	local total, limited = M.Total(list, wave)
	T.eq(total, 3, "the sum")
	T.eq(limited, false, "within the limits")
	total, limited = M.Total({ { seconds = -(wave + 4) } }, wave)
	T.eq(total, -wave, "a wave sooner at most")
	T.eq(limited, true, "limited")
	total, limited = M.Total({ { seconds = M.MOST_PENALTY + 3 } }, wave)
	T.eq(total, M.MOST_PENALTY, "MOST_PENALTY later at most")
	T.eq(limited, true, "limited")
end)

T.test("each reason is told in words, with its count", function()
	T.eq(M.Describe({ reason = M.KILLS, count = 1 }), "1 kill", "one")
	T.eq(M.Describe({ reason = M.KILLS, count = 3 }), "3 kills", "several")
	T.eq(M.Describe({ reason = M.CAPTURE, count = 1 }), "Captured a point", "a capture")
	T.eq(M.Describe({ reason = M.DEFENSE, count = 2 }), "Defended a point (2)", "defenses")
	T.eq(M.Describe({ reason = M.FINISHED_OFF, count = 1 }), "Finished off by an enemy", "finished off")
	T.eq(M.Describe({ reason = M.SUICIDE, count = 1 }), "Suicide", "a suicide")
end)

T.test("seconds are told signed: sooner with a minus, later with a plus", function()
	T.eq(M.Seconds(-2), "-2 s", "sooner")
	T.eq(M.Seconds(5), "+5 s", "later")
	T.eq(M.Seconds(-1.5), "-1.5 s", "a fraction kept")
end)

T.finish()
