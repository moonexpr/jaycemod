-- game_timer: the clocks of a round and of each team, kept on the server and
-- read through what it networks.
local T = dofile ("tests/harness.lua")

local RED, BLUE = 2, 3
local now, networked, outcomes, expired

CurTime = function () return now end
SetGlobal2Float = function (name, value) networked [name] = value end
GetGlobal2Float = function (name, default)
	local value = networked [name]
	if value == nil then return default end
	return value
end
hook = { Run = function (name, id) if name == "GameTimerExpired" then expired [#expired + 1] = id end end }
round_manager = { RoundOutcome = function (outcome) outcomes [#outcomes + 1] = outcome end }

dofile ("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/game_timer.lua")
local Timer = package.loaded.game_timer

local function Fresh ()
	now, networked, outcomes, expired = 100, {}, {}, {}
	Timer.StopAll ()
	networked, outcomes, expired = {}, {}, {}
end

T.test ("a clock counts down from when it starts", function ()
	Fresh ()
	Timer.Start (Timer.ROUND, 60)
	T.eq (Timer.Remaining (Timer.ROUND), 60, "full")
	T.eq (Timer.EndTime (Timer.ROUND), 160, "when it ends")
	T.eq (Timer.Running (Timer.ROUND), true, "running")
	now = 130
	T.eq (Timer.Remaining (Timer.ROUND), 30, "half")
end)

T.test ("a clock not started reads nothing", function ()
	Fresh ()
	T.eq (Timer.Remaining ("none"), 0, "no time")
	T.eq (Timer.EndTime ("none"), 0, "no end")
	T.eq (Timer.Running ("none"), false, "not running")
	T.eq (Timer.Paused ("none"), false, "not paused")
end)

T.test ("a team's clock is its own", function ()
	Fresh ()
	T.eq (Timer.TeamClock (RED) ~= Timer.TeamClock (BLUE), true, "one each")
	T.eq (Timer.TeamClock (RED) ~= Timer.ROUND, true, "apart from the round's")
	Timer.Start (Timer.TeamClock (RED), 10)
	Timer.Start (Timer.TeamClock (BLUE), 20)
	T.eq (Timer.Remaining (Timer.TeamClock (RED)), 10, "RED's")
	T.eq (Timer.Remaining (Timer.TeamClock (BLUE)), 20, "BLU's")
end)

T.test ("a clock with an outcome closes the round when it runs out, once", function ()
	Fresh ()
	local outcome = { team = RED, reason = 1 }
	Timer.Start (Timer.TeamClock (RED), 10, { outcome = outcome })
	now = 109
	Timer.Think ()
	T.eq (#outcomes, 0, "not yet")
	now = 110
	Timer.Think ()
	T.eq (outcomes [1], outcome, "the clock's outcome")
	T.eq (Timer.Running (Timer.TeamClock (RED)), false, "stopped")
	Timer.Think ()
	T.eq (#outcomes, 1, "once")
end)

T.test ("a clock with no outcome only says it ran out", function ()
	Fresh ()
	Timer.Start ("setup", 5)
	now = 105
	Timer.Think ()
	T.eq (expired [1], "setup", "told")
	T.eq (#outcomes, 0, "the round goes on")
end)

T.test ("a clock started as it expires another is kept", function ()
	Fresh ()
	Timer.Start ("a", 1)
	hook.Run = function (name, id)
		if name == "GameTimerExpired" and id == "a" then Timer.Start ("b", 5) end
	end
	now = 101
	Timer.Think ()
	hook.Run = function (name, id) if name == "GameTimerExpired" then expired [#expired + 1] = id end end
	T.eq (Timer.Remaining ("b"), 5, "the new clock")
end)

T.test ("a paused clock holds its time and never runs out", function ()
	Fresh ()
	Timer.Start ("c", 10)
	now = 104
	Timer.Pause ("c")
	T.eq (Timer.Paused ("c"), true, "paused")
	T.eq (Timer.Running ("c"), true, "still a clock")
	T.eq (Timer.EndTime ("c"), 0, "no end while paused")
	now = 500
	Timer.Think ()
	T.eq (Timer.Remaining ("c"), 6, "held")
	T.eq (#expired, 0, "not run out")
	Timer.Resume ("c")
	T.eq (Timer.Paused ("c"), false, "resumed")
	T.eq (Timer.EndTime ("c"), 506, "the time it had left")
end)

T.test ("a clock may start paused", function ()
	Fresh ()
	Timer.Start ("c", 180, { paused = true })
	now = 200
	T.eq (Timer.Remaining ("c"), 180, "full")
end)

T.test ("time can be added to a clock, running or paused, or set", function ()
	Fresh ()
	Timer.Start ("c", 10)
	Timer.AddTime ("c", 5)
	T.eq (Timer.Remaining ("c"), 15, "running")
	Timer.Pause ("c")
	Timer.AddTime ("c", -5)
	T.eq (Timer.Remaining ("c"), 10, "paused")
	Timer.SetTime ("c", 3)
	T.eq (Timer.Remaining ("c"), 3, "set, paused")
	Timer.Resume ("c")
	Timer.SetTime ("c", 7)
	T.eq (Timer.Remaining ("c"), 7, "set, running")
end)

T.test ("changing a clock that is not running does nothing", function ()
	Fresh ()
	Timer.AddTime ("none", 5)
	Timer.SetTime ("none", 5)
	Timer.Pause ("none")
	Timer.Resume ("none")
	T.eq (Timer.Running ("none"), false, "still none")
end)

T.test ("stopping clears a clock; StopAll clears them all", function ()
	Fresh ()
	Timer.Start ("a", 10)
	Timer.Start ("b", 10, { paused = true })
	Timer.Stop ("a")
	T.eq (Timer.Running ("a"), false, "stopped")
	T.eq (Timer.Remaining ("a"), 0, "no time")
	T.eq (Timer.Running ("b"), true, "the other runs on")
	Timer.StopAll ()
	T.eq (Timer.Running ("b"), false, "all")
	now = 500
	Timer.Think ()
	T.eq (#expired, 0, "none runs out")
end)

T.finish ()
