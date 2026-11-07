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

T.test("the map's info_rooms stand over the classes the war finds, a point's owner holding its room", function()
	local f = io.open(T.ROOT .. "features/aiwar/sv_room_hints.lua", "r")
	T.eq(f ~= nil, true, "the war reads the map's hints")
	local hints = f and f:read("*a") or ""
	if f then f:close() end
	T.eq(hints:find('ents.FindByClass("info_room")', 1, true) ~= nil, true, "each info_room")
	T.eq(hints:find("Hints.Place(", 1, true) ~= nil, true, "placed in the war's rooms")
	T.eq(hints:find("Hints.Override(found.classed, self:RoomHints()", 1, true) ~= nil, true, "over the classes found")
	T.eq(hints:find('if not WS.FeatureLoaded("capture") then return nil end', 1, true) ~= nil, true,
		"a point's owner where the map has points")
	local root = io.open(T.ROOT .. "features/aiwar/sv.lua", "r"):read("*a")
	T.eq(root:find('Part("sv_room_hints", Controller)', 1, true) ~= nil, true, "a part of the war")
	T.eq(marks:find("label = hinted and hinted.label", 1, true) ~= nil, true, "a squad's room carries its label")
end)

T.test("info_room keeps the map's word on its room: label, class, team and control point", function()
	local f = io.open(T.ROOT .. "../entities/entities/info_room.lua", "r")
	T.eq(f ~= nil, true, "the entity")
	local room = f and f:read("*a") or ""
	if f then f:close() end
	for _, key in ipairs({ '"label"', '"class"', '"teamnum"', '"controlpoint"' }) do
		T.eq(room:find(key, 1, true) ~= nil, true, "keyvalue " .. key)
	end
	T.eq(room:find("TRANSMIT_NEVER", 1, true) ~= nil, true, "the server's alone")
end)

T.finish()