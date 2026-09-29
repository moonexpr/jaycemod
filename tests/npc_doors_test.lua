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

T.finish()
