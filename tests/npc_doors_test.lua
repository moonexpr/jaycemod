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

T.test("only a door shut and locked blocks routes, to everyone", function()
	T.eq(Doors.BlockedTeam({ closed = true, locked = true }), Doors.ANY, "shut and locked")
	T.eq(Doors.BlockedTeam({ closed = true, locked = false }), nil, "shut: it opens as a soldier reaches it")
	T.eq(Doors.BlockedTeam({ closed = false, locked = true }), nil, "locked open")
	T.eq(Doors.BlockedTeam({ closed = true, controlled = true, owner = 3 }), nil, "a team's own spawn door does not shut it in")
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

T.finish()
