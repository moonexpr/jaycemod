-- foundation.payload: the team_train_watcher's decisions (team_train_watcher.cpp).
local T = dofile("tests/harness.lua")
local P = T.require("foundation.payload")
local Capture = T.require("foundation.capture")
local Master = T.require("foundation.capture.master")
local Teams = T.require("foundation.teams")
local NEITHER = T.require("foundation.rounds").RESTRICT_NEITHER

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE

-- HandleTrainMovement -----------------------------------------------------------

local function Speed(cappers, hill, current, receding, startReceding)
	return P.TrainSpeed({ numCappers = cappers, hill = hill, currentSpeed = current, receding = receding }, startReceding)
end

T.test("pushers set 0.55, 0.77 and 1.0 of top speed", function()
	T.eq(Speed(1, P.HILL_NONE, 0, false), 0.55)
	T.eq(Speed(2, P.HILL_NONE, 0, false), 0.77)
	T.eq(Speed(3, P.HILL_NONE, 0, false), 1.0)
	T.eq(Speed(7, P.HILL_NONE, 0, false), 1.0)
end)

T.test("pushers on a downhill run at full speed", function()
	T.eq(Speed(1, P.HILL_DOWN, 0, false), 1.0)
end)

T.test("a blocked cart stops unless it is on a downhill", function()
	T.eq(Speed(P.CAPPERS_BLOCKED, P.HILL_NONE, 0.55, false), 0)
	T.eq(Speed(P.CAPPERS_BLOCKED, P.HILL_UP, 0.55, false), 0)
	T.eq(Speed(P.CAPPERS_BLOCKED, P.HILL_DOWN, 0.55, false), 1.0)
end)

T.test("an unpushed cart moving forward stops, or keeps rolling downhill", function()
	T.eq(Speed(0, P.HILL_NONE, 0.55, false), 0)
	T.eq(Speed(0, P.HILL_DOWN, 0.55, false), 1.0)
end)

T.test("an unpushed cart rolls back down an uphill at full speed", function()
	T.eq(Speed(0, P.HILL_UP, 0, false), -1.0)
end)

T.test("a receding cart resumes its slow recede", function()
	T.eq(Speed(0, P.HILL_NONE, 0, true), -0.1)
	T.eq(Speed(0, P.HILL_NONE, 0, false), 0)
end)

T.test("starting to recede sets -0.1 and the receding flag", function()
	local speed, receding = Speed(0, P.HILL_NONE, 0, false, true)
	T.eq(speed, -0.1)
	T.eq(receding, true)
end)

T.test("pushers clear the receding flag", function()
	local _, receding = Speed(1, P.HILL_NONE, -0.1, true)
	T.eq(receding, false)
end)

T.test("a receding cart with nobody pushing keeps receding, even downhill", function()
	T.eq(Speed(0, P.HILL_DOWN, -0.1, true), -0.1)
end)

T.test("a forward speed clears receding even with nobody pushing", function()
	local speed, receding = Speed(P.CAPPERS_BLOCKED, P.HILL_DOWN, -0.1, true)
	T.eq(speed, 1.0)
	T.eq(receding, false)
end)

-- Speed levels for the HUD ------------------------------------------------------------

local LEVELS = { 1, 60, 80 }

T.test("speed levels split at hud_min_speed_level_1..3", function()
	T.eq(P.SpeedLevel(0, 0, LEVELS), 0)
	T.eq(P.SpeedLevel(1, 1, LEVELS), 0)
	T.eq(P.SpeedLevel(30, 30, LEVELS), 1)
	T.eq(P.SpeedLevel(60, 60, LEVELS), 1)
	T.eq(P.SpeedLevel(70, 70, LEVELS), 2)
	T.eq(P.SpeedLevel(90, 90, LEVELS), 3)
end)

T.test("moving backwards is the backwards level, unless stopped at a dead end", function()
	T.eq(P.SpeedLevel(-20, -20, LEVELS), P.SPEED_LEVEL_BACKWARDS)
	T.eq(P.SpeedLevel(-20, 0, LEVELS), 0)
end)

-- Recede timing -------------------------------------------------------------------

T.test("recede delay: overtime length, map's train_recede_time, else the convar", function()
	T.eq(P.RecedeDelay(true, 12, 30, 5), 5)
	T.eq(P.RecedeDelay(false, 12, 30, 5), 12)
	T.eq(P.RecedeDelay(false, 0, 30, 5), 30)
end)

T.test("overtime shortens a longer pending recede to the overtime length", function()
	T.eq(P.OvertimeRecedeAt(130, 100, 5), 105)
	T.eq(P.OvertimeRecedeAt(103, 100, 5), 103)
end)

-- Progress along the path ----------------------------------------------------------

T.test("the node the train heads for: the next one, or its own when reversing", function()
	T.eq(P.TargetIndex(2, 10, 5), 3)
	T.eq(P.TargetIndex(2, 0, 5), 3)
	T.eq(P.TargetIndex(2, -10, 5), 2)
	T.eq(P.TargetIndex(5, 10, 5), 5)
end)

T.test("passing a node forward makes it current; backward, the one before it", function()
	T.eq(P.PassedIndex(4, 10), 4)
	T.eq(P.PassedIndex(4, -10), 3)
	T.eq(P.PassedIndex(1, -10), 1)
end)

T.test("distance to goal is to the target node, then along the path", function()
	local distanceAt = { 0, 100, 250, 400 }
	T.eq(P.DistanceToGoal(400, distanceAt, 3, 40), 40 + 150)
	T.near(P.Progress(400, 190), 1 - 190 / 400)
	T.eq(P.Progress(400, 500), 0)
	T.eq(P.Progress(400, 0), 1)
end)

-- Approach alerts ----------------------------------------------------------------------

local function Links(...)
	local links = {}
	for i, d in ipairs({ ... }) do links[i] = { distance = d, alerted = false } end
	return links
end

T.test("an alert plays once the train comes within 750 of a checkpoint", function()
	local links = Links(2000)
	T.eq(#P.AlertsDue(links, 1000, true), 0)
	local due = P.AlertsDue(links, 1300, true)
	T.eq(#due, 1)
	T.eq(due[1], 1)
	T.eq(#P.AlertsDue(links, 1400, true), 0)
end)

T.test("no alert once past the checkpoint", function()
	T.eq(#P.AlertsDue(Links(2000), 2100, true), 0)
end)

T.test("the alert re-arms only after receding twice the alert distance", function()
	local links = Links(2000)
	P.AlertsDue(links, 1300, true)
	P.AlertsDue(links, 1000, true)
	T.eq(#P.AlertsDue(links, 1300, true), 0)
	P.AlertsDue(links, 400, true)
	T.eq(#P.AlertsDue(links, 1300, true), 1)
end)

T.test("a train that cannot recede re-arms as soon as it is outside the alert distance", function()
	local links = Links(2000)
	P.AlertsDue(links, 1300, false)
	P.AlertsDue(links, 1200, false)
	T.eq(#P.AlertsDue(links, 1300, false), 1)
end)

-- Capture alarm ---------------------------------------------------------------------

local function Actions(list)
	return table.concat(list, ",")
end

T.test("the alarm starts within 200 of the goal and stops outside it", function()
	local a = P.NewAlarm()
	T.eq(Actions(P.AlarmStep(a, 300, true, true, true, 0)), "")
	T.eq(Actions(P.AlarmStep(a, 150, true, true, true, 1)), "start")
	T.eq(Actions(P.AlarmStep(a, 150, true, true, true, 2)), "")
	T.eq(Actions(P.AlarmStep(a, 250, true, true, true, 3)), "stop")
	T.eq(Actions(P.AlarmStep(a, 150, true, true, true, 4)), "start")
end)

T.test("no alarm without linked control points", function()
	T.eq(Actions(P.AlarmStep(P.NewAlarm(), 150, true, true, false, 0)), "")
end)

T.test("the alarm stops when the round is not running and does not restart", function()
	local a = P.NewAlarm()
	P.AlarmStep(a, 150, true, true, true, 0)
	T.eq(Actions(P.AlarmStep(a, 150, false, true, true, 1)), "stop")
	T.eq(Actions(P.AlarmStep(a, 150, false, true, true, 2)), "")
	T.eq(Actions(P.AlarmStep(a, 150, true, true, true, 3)), "")
end)

T.test("a receding train keeps the loop playing past 18s", function()
	local a = P.NewAlarm()
	P.AlarmStep(a, 150, true, true, true, 0)
	T.eq(Actions(P.AlarmStep(a, 150, true, true, true, 30)), "")
end)

T.test("a train that cannot recede loops 18s, then plays a single every 8s", function()
	local a = P.NewAlarm()
	P.AlarmStep(a, 150, true, false, true, 0)
	T.eq(Actions(P.AlarmStep(a, 150, true, false, true, 18)), "")
	T.eq(Actions(P.AlarmStep(a, 150, true, false, true, 18.1)), "stop")
	T.eq(Actions(P.AlarmStep(a, 150, true, false, true, 20)), "")
	T.eq(Actions(P.AlarmStep(a, 150, true, false, true, 26.1)), "single")
	T.eq(Actions(P.AlarmStep(a, 150, true, false, true, 30)), "")
	T.eq(Actions(P.AlarmStep(a, 150, true, false, true, 34.1)), "single")
	T.eq(Actions(P.AlarmStep(a, 250, true, false, true, 35)), "stop")
	T.eq(Actions(P.AlarmStep(a, 250, true, false, true, 50)), "")
end)

T.test("StopAlarm stops a playing loop and pending singles, and is quiet otherwise", function()
	local a = P.NewAlarm()
	T.eq(Actions(P.StopAlarm(a)), "")
	P.AlarmStep(a, 150, true, true, true, 0)
	T.eq(Actions(P.StopAlarm(a)), "stop")
	T.eq(a.playing, false)
	T.eq(a.played, true)
end)

-- Hill data for the HUD (WatcherActivate) --------------------------------------------

local FLAT, UP, DOWN = P.HILL_NONE, P.HILL_UP, P.HILL_DOWN

local function Nodes(spec)
	local nodes, d = {}, 0
	for i, s in ipairs(spec) do
		d = d + (i > 1 and 100 or 0)
		nodes[i] = { distance = d, hill = s }
	end
	return nodes
end

T.test("no hills on a flat track", function()
	T.eq(#P.HillSegments(Nodes({ FLAT, FLAT, FLAT, FLAT }), 300), 0)
end)

T.test("an uphill run is reported from its first node to the node before it ends", function()
	local hills = P.HillSegments(Nodes({ FLAT, FLAT, UP, UP, FLAT, FLAT }), 500)
	T.eq(#hills, 1)
	T.near(hills[1].from, 200 / 500 + 0.005)
	T.near(hills[1].to, 300 / 500 - 0.005)
	T.eq(hills[1].down, false)
end)

T.test("a single hill node reaches to the next node", function()
	local hills = P.HillSegments(Nodes({ FLAT, DOWN, FLAT, FLAT }), 300)
	T.eq(#hills, 1)
	T.near(hills[1].from, 100 / 300 + 0.005)
	T.near(hills[1].to, 200 / 300 - 0.005)
	T.eq(hills[1].down, true)
end)

T.test("a hill running to the goal ends at the path's end", function()
	local hills = P.HillSegments(Nodes({ FLAT, FLAT, UP, UP }), 300)
	T.eq(#hills, 1)
	T.near(hills[1].to, 1 - 0.005)
end)

T.test("an uphill straight into a downhill makes two hills", function()
	local hills = P.HillSegments(Nodes({ FLAT, UP, UP, DOWN, DOWN, FLAT }), 500)
	T.eq(#hills, 2)
	T.eq(hills[1].down, false)
	T.eq(hills[2].down, true)
	T.near(hills[2].from, 300 / 500 + 0.005)
end)

-- Final point in map (WatcherThink's bFinalPointInMap) --------------------------------
-- These rules moved to the capture system (PointSet:TeamOwnsAll and the
-- Master), which the watcher asks through the capture controller.

local NO_FLAGS = 0
local function first(n) return 1 end

-- Points "p1".."pn" in index order; each owner a team, or { team, group }.
local function Points(...)
	local points = {}
	for i, o in ipairs({ ... }) do
		local owner, group = o, 0
		if type(o) == "table" then owner, group = o[1], o[2] end
		points[i] = {
			id = "p" .. i,
			index = i,
			defaultOwner = owner,
			startLocked = false,
			group = group,
			warnOnCap = Capture.CP_WARN.NORMAL,
			warnSound = "",
			printName = "",
			spawnflags = NO_FLAGS,
			previous = {},
			sounds = {},
			capSounds = {},
		}
	end
	return Capture.New({
		caplinear = true,
		points = points,
	})
end

-- A master with mini-rounds { name, priority, restrict, points }.
local function NewMaster(rounds)
	return Master.New({
		restrict = NOBODY,
		switchTeams = false,
		scoreStyle = Master.SCORE_PER_ROUND,
		playAllRounds = false,
		partialCapRate = 0,
		capLayout = "",
		disabled = false,
		rounds = rounds or {},
	})
end

local function Round(name, priority, restrict, points)
	return {
		name = name,
		priority = priority,
		restrict = restrict,
		printName = "",
		points = points,
	}
end

local NO_HISTORY = {
	previous = {},
	first = nil,
}

T.test("TeamOwnsAllPoints: one owner of every point, else nobody", function()
	local all = Points(BLU, BLU, BLU)
	T.eq(all:TeamOwnsAll(all:Ids()), BLU)
	local split = Points(BLU, RED, BLU)
	T.eq(split:TeamOwnsAll(split:Ids()), NOBODY)
	local neutral = Points(NOBODY, NOBODY)
	T.eq(neutral:TeamOwnsAll(neutral:Ids()), NOBODY)
end)

T.test("TeamOwnsAllPoints with an override predicts a capture", function()
	local set = Points(BLU, BLU, RED)
	T.eq(set:TeamOwnsAll(set:Ids(), "p3", BLU), BLU)
	local behind = Points(BLU, RED, RED)
	T.eq(behind:TeamOwnsAll(behind:Ids(), "p3", BLU), NOBODY)
end)

T.test("TeamOwnsAllPoints: any fully owned group wins", function()
	local set = Points({ RED, 0 }, { BLU, 0 }, { BLU, 1 })
	T.eq(set:TeamOwnsAll(set:Ids()), BLU)
end)

T.test("a round is unplayable once a team that may win it owns every point", function()
	local function Playable(set, restrict)
		return NewMaster({ Round("r", 0, restrict, set:Ids()) }):NumPlayable(set) == 1
	end
	T.eq(Playable(Points(RED, RED), RED), true)
	T.eq(Playable(Points(BLU, BLU), RED), false)
	T.eq(Playable(Points(BLU, BLU), NEITHER), true)
	T.eq(Playable(Points(BLU, RED), NOBODY), true)
end)

T.test("final point without mini-rounds: capturing it would win", function()
	T.eq(NewMaster():FinalPoint(Points(BLU, BLU, RED), "p3", { BLU }), true)
	T.eq(NewMaster():FinalPoint(Points(BLU, RED, RED), "p2", { BLU }), false)
end)

T.test("final point with mini-rounds: only in the last playable round", function()
	local set = Points(BLU, RED, RED)
	local master = NewMaster({
		Round("a", 0, RED, { "p1" }),
		Round("b", 2, RED, { "p2" }),
		Round("c", 1, RED, { "p3" }),
	})
	T.eq(master:RoundActivate(set, NO_HISTORY, first), "b", "round b plays")
	T.eq(master:FinalPoint(set, "p2", { BLU }), false, "round c is still playable")
	set:SetOwner("p3", BLU, Capture.CAUSE_FORCE)
	T.eq(master:FinalPoint(set, "p2", { BLU }), true, "the last playable round")
end)

-- Admin controls (the Game Rules editor) ---------------------------------------

T.test("the next checkpoint is the first one past the cart", function()
	local links = { { distance = 0, index = 1 }, { distance = 800, index = 6 }, { distance = 2000, index = 14 } }
	T.eq(P.NextCheckpoint(links, 100).index, 6, "the second")
	T.eq(P.NextCheckpoint(links, 800).index, 14, "a cart sitting on one goes on to the next")
	T.eq(P.NextCheckpoint(links, 2000), nil, "none past the last")
end)

-- The Game Rules editor's retract: a cart within RETRACT_NEAR past the
-- last point it took gives the point back and goes to the checkpoint before
-- it (or the start); farther on, it only goes back to that point.
T.test("retracting just past a point gives it back and returns the cart to the checkpoint before", function()
	local links = { { distance = 800, index = 6 }, { distance = 2000, index = 14 }, { distance = 3000, index = 20 } }
	local plan = P.RetractPlan(links, 2000 + P.RETRACT_NEAR)
	T.eq(plan.uncap, links[2], "the point just taken")
	T.eq(plan.to, links[1], "the checkpoint before it")
	plan = P.RetractPlan(links, 900)
	T.eq(plan.uncap, links[1], "the first point")
	T.eq(plan.to, nil, "back to the start")
end)

T.test("retracting farther past a point only returns the cart to it", function()
	local links = { { distance = 800, index = 6 }, { distance = 2000, index = 14 } }
	local plan = P.RetractPlan(links, 2000 + P.RETRACT_NEAR + 1)
	T.eq(plan.uncap, nil, "nothing given back")
	T.eq(plan.to, links[2], "back to the last point taken")
end)

T.test("a cart that has taken no point goes back to the start", function()
	local plan = P.RetractPlan({ { distance = 800, index = 6 } }, 300)
	T.eq(plan.uncap, nil)
	T.eq(plan.to, nil)
	T.eq(P.RETRACT_SLACK, 300, "the attackers get five minutes for a point given back")
end)

T.test("the cart's top speed is the map's times the admin's scale, faster while advancing", function()
	T.eq(P.MaxSpeed(90, 1, false), 90, "the map's")
	T.eq(P.MaxSpeed(90, 2, false), 180, "doubled")
	T.eq(P.MaxSpeed(90, 1, true), 90 * P.ADVANCE_SPEED_SCALE, "advancing")
	T.eq(P.MaxSpeed(90, P.CART_SPEED_MAX * 10, false), 90 * P.CART_SPEED_MAX, "scale clamped high")
	T.eq(P.MaxSpeed(90, 0, false), 90 * P.CART_SPEED_MIN, "scale clamped low")
end)

T.finish()
