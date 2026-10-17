-- foundation.npc.doors: TF2's rule for which doors close the nav mesh to
-- whom (CTFNavMesh::ComputeBlockedAreas).
local T = dofile("tests/harness.lua")
local Doors = T.require("foundation.npc.doors")

local RED, BLUE = 2, 3

T.test("a door is closed at the bottom of its travel or on its way there", function()
	T.eq(Doors.IsClosed(Doors.TS_AT_BOTTOM), true, "shut")
	T.eq(Doors.IsClosed(Doors.TS_GOING_DOWN), true, "closing")
	T.eq(Doors.IsClosed(Doors.TS_AT_TOP), false, "open")
	T.eq(Doors.IsClosed(Doors.TS_GOING_UP), false, "opening")
end)

T.test("a door is a floor when it is flat and wide: a bridge, not a door, gate or handrail", function()
	T.eq(Doors.IsFloor({ x = 82, y = 426, z = 10 }), true, "cp_steel's bridge")
	T.eq(Doors.IsFloor({ x = 194, y = 6, z = 138 }), false, "a spawn door")
	T.eq(Doors.IsFloor({ x = 6, y = 410, z = 6 }), false, "a handrail: thin both ways")
	T.eq(Doors.IsFloor({ x = 189, y = 106, z = 90 }), false, "a gate")
end)

T.test("a floor blocks its span to everyone until it is laid out (closed), locked or not", function()
	T.eq(Doors.BlockedTeam({ floor = true, closed = false }), Doors.ANY, "drawn back: no floor there")
	T.eq(Doors.BlockedTeam({ floor = true, closed = true }), nil, "laid out")
	T.eq(Doors.BlockedTeam({ floor = true, closed = true, locked = true }), nil, "laid out and locked: still a floor")
end)

T.test("a door shut and locked blocks routes, to everyone", function()
	T.eq(Doors.BlockedTeam({ closed = true, locked = true }), Doors.ANY, "shut and locked")
	T.eq(Doors.BlockedTeam({ closed = true, locked = false, touchOpens = true }), nil, "shut: it opens as a soldier reaches it")
	T.eq(Doors.BlockedTeam({ closed = false, locked = true }), nil, "locked open")
	T.eq(Doors.BlockedTeam({ closed = true, controlled = true, owner = 3 }), nil, "a team's own spawn door does not shut it in")
end)

-- TF2's rule (CTFNavMesh::ComputeBlockedAreas): a shut door that nothing a
-- soldier does opens, only the map's logic (cp_steel's point_a_brushdoor,
-- spawnflags Toggle alone), walls off its areas until it opens.
T.test("a shut door neither touch, use nor a trigger opens blocks routes, to everyone", function()
	T.eq(Doors.BlockedTeam({ closed = true }), Doors.ANY, "only the map's logic opens it")
	T.eq(Doors.BlockedTeam({ closed = true, touchOpens = true }), nil, "touch or use opens it")
	T.eq(Doors.BlockedTeam({ closed = true, controlled = true }), nil, "a trigger opens it")
	T.eq(Doors.BlockedTeam({ closed = false }), nil, "open")
end)

T.test("a door's spawnflags say whether a soldier's touch or use opens it", function()
	T.eq(Doors.TouchOpens(1024), true, "Touch Opens")
	T.eq(Doors.TouchOpens(256), true, "Use Opens")
	T.eq(Doors.TouchOpens(32), false, "Toggle alone: the map's logic")
	T.eq(Doors.TouchOpens(1024 + 512), false, "Touch Opens, but NPCs can't")
end)

T.test("a shut door no trigger opens walls in setup's ground", function()
	T.eq(Doors.IsWall({ closed = true, controlled = false }), true, "a setup gate")
	T.eq(Doors.IsWall({ closed = true, controlled = true }), false, "a spawn door")
	T.eq(Doors.IsWall({ closed = false, controlled = false }), false, "once opened")
end)

T.test("an area is blocked to a team by any of its doors that blocks that team or everyone", function()
	T.eq(Doors.Blocks(nil, RED), false, "no doors")
	T.eq(Doors.Blocks({ BLUE }, RED), false, "BLU's problem")
	T.eq(Doors.Blocks({ BLUE, RED }, RED), true, "one of them")
	T.eq(Doors.Blocks({ Doors.ANY }, BLUE), true, "a wall")
end)

-- A trigger opens a door when one of its outputs sends that door Open,
-- Toggle or Unlock (a spawn door's OnStartTouchAll -> Open); a trigger
-- beside a door that only closes it (pl_bloodwater's
-- door1_door_close_trigger) does not, so the door it shut stays shut.
T.test("a trigger opens a door only through an output that opens that door", function()
	local function Out(target, input) return { name = "OnStartTouch", target = target, input = input } end
	T.eq(Doors.Opens({ Out("door6_door", "Open") }, "door6_door"), true, "Open")
	T.eq(Doors.Opens({ Out("Door6_Door", "toggle") }, "door6_door"), true, "Toggle, whatever the case")
	T.eq(Doors.Opens({ Out("door6_door", "Unlock") }, "door6_door"), true, "Unlock")
	T.eq(Doors.Opens({ Out("door1_door", "Close") }, "door1_door"), false, "a trigger that closes it")
	T.eq(Doors.Opens({ Out("other_door", "Open") }, "door1_door"), false, "another door")
	T.eq(Doors.Opens({}, "door1_door"), false, "no outputs")
	T.eq(Doors.Opens({ Out("door1_door", "Open") }, ""), false, "an unnamed door no output can name")
end)

-- Source names a target with a trailing * for every name it starts
-- (pl_swiftwater's blue_spawn_doortrigger_1 opens blue_spawn_door_1*,
-- both its doors); BLU stood at doors that never opened.
T.test("an output naming a door with a trailing * opens every door its prefix names", function()
	local function Out(target, input) return { name = "OnStartTouchAll", target = target, input = input } end
	T.eq(Doors.Opens({ Out("blue_spawn_door_1*", "Open") }, "blue_spawn_door_1a"), true, "1a")
	T.eq(Doors.Opens({ Out("blue_spawn_door_1*", "Open") }, "Blue_Spawn_Door_1B"), true, "1b, whatever the case")
	T.eq(Doors.Opens({ Out("blue_spawn_door_1*", "Open") }, "blue_spawn_door_2a"), false, "not another door")
	T.eq(Doors.Opens({ Out("blue_spawn_door_1*", "Close") }, "blue_spawn_door_1a"), false, "closing it")
end)

-- Blocked maps: area id -> the teams a blocker closes it to.
T.test("the areas whose blocking changed: shut, opened, or closed to other teams", function()
	local before = {
		[1] = { Doors.ANY },
		[2] = { RED },
		[3] = { BLUE, RED },
	}
	local after = {
		[2] = { RED },
		[3] = { RED, BLUE },
		[4] = { Doors.ANY },
		[5] = {},
	}
	local changed = Doors.Changed(before, after)
	T.eq(changed[1], true, "opened")
	T.eq(changed[4], true, "shut")
	T.eq(changed[2], nil, "the same team")
	T.eq(changed[3], nil, "the same teams, another order")
	T.eq(changed[5], nil, "an empty list blocks no one, as no entry")
end)

T.test("nothing changed between two equal maps", function()
	T.eq(next(Doors.Changed({ [7] = { Doors.ANY } }, { [7] = { Doors.ANY } })), nil, "none")
end)

T.finish()
