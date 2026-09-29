-- foundation.npc.doors: TF2's rule for which doors close the nav mesh to
-- whom (CTFNavMesh::ComputeBlockedAreas).
local T = dofile("tests/harness.lua")
local Doors = T.require("foundation.npc.doors")

local RED, BLUE = 2, 3
local function EnemyOf(team) return ({ [RED] = BLUE, [BLUE] = RED })[team] end

T.test("a door is closed at the bottom of its travel or on its way there", function()
	T.eq(Doors.IsClosed(Doors.TS_AT_BOTTOM), true, "shut")
	T.eq(Doors.IsClosed(Doors.TS_GOING_DOWN), true, "closing")
	T.eq(Doors.IsClosed(Doors.TS_AT_TOP), false, "open")
	T.eq(Doors.IsClosed(Doors.TS_GOING_UP), false, "opening")
end)

T.test("a shut door no trigger opens is a wall to everyone: a setup gate", function()
	T.eq(Doors.BlockedTeam({ closed = true, controlled = false }, EnemyOf), Doors.ANY, "a gate")
	T.eq(Doors.BlockedTeam({ closed = false, controlled = false }, EnemyOf), nil, "once map logic opens it")
end)

T.test("a door a trigger opens is no wall, unless the trigger admits one team only", function()
	T.eq(Doors.BlockedTeam({ closed = true, controlled = true }, EnemyOf), nil, "a door anyone opens")
	T.eq(Doors.BlockedTeam({ closed = true, controlled = true, owner = BLUE }, EnemyOf), RED, "BLU's spawn door shuts RED out")
	T.eq(Doors.BlockedTeam({ closed = false, controlled = true, owner = RED }, EnemyOf), BLUE, "even while it stands open")
end)

T.test("an area is blocked to a team by any of its doors that blocks that team or everyone", function()
	T.eq(Doors.Blocks(nil, RED), false, "no doors")
	T.eq(Doors.Blocks({ BLUE }, RED), false, "BLU's problem")
	T.eq(Doors.Blocks({ BLUE, RED }, RED), true, "one of them")
	T.eq(Doors.Blocks({ Doors.ANY }, BLUE), true, "a wall")
end)

T.finish()
