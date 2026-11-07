-- The room as a squad takes it (Controller:RoomForSquad, features/aiwar/sv_marks.lua): its
-- entrances carry its team's flow and the enemy's, so an assault stages off the enemy's ways in.
local T = dofile("tests/harness.lua")

local file = assert(io.open(T.ROOT .. "features/aiwar/sv_marks.lua", "r"))
local marks = file:read("*a")
file:close()

T.test("each entrance carries the squad's flow and the enemy's into the room", function()
	T.eq(marks:find("entrances[i] = { pos = exits[i], flow = 0, enemyFlow = 0 }", 1, true) ~= nil, true, "both, from none")
	T.eq(marks:find("local enemyName = TEAM_NAMES[Teams.EnemyOf(team)]", 1, true) ~= nil, true, "the enemy is the other team")
	T.eq(marks:find("if e.team == enemyName then nearest.enemyFlow = nearest.enemyFlow + e.paths end", 1, true) ~= nil,
		true, "its routes and breaches entering by each")
end)

T.test("what one walking up to an entrance sees inside, for an ambush to hide from", function()
	T.eq(marks:find("local function Watched(p, entrance)", 1, true) ~= nil, true, "watched")
	T.eq(marks:find("for _, along in ipairs(LOOKOUT_ALONG) do", 1, true) ~= nil, true, "from lookouts along its approach")
	T.eq(marks:find("watched = Watched", 1, true) ~= nil, true, "given with the room")
end)

T.finish()
