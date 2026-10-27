-- nextsoldier.route_record: route searches recorded on the server, read
-- back and replayed offline with the same solver and cost strategy.
local T = dofile("tests/harness.lua")
local Record = nextsoldier.route_record
local Pathfinder = graph.pathfinder
local HL2 = T.require("foundation.wetsands.path.hl2")
local TFBot = T.require("foundation.wetsands.path.tfbot")

local RED, BLUE = 2, 3
local CELL = 100

-- A row of areas 1 - 2 - 3 - 4, and a way round 2 through 5 (1 - 5 - 3),
-- each CELL apart, all level.
local function Link(to, distance) return { to = to, distance = distance or CELL, rise = 0 } end

local function Mesh()
	return {
		[1] = { x = 0, y = 0, z = 0, attributes = 0, links = { Link(2), Link(5, 2 * CELL) } },
		[2] = { x = CELL, y = 0, z = 0, attributes = 0, links = { Link(1), Link(3) } },
		[3] = { x = 2 * CELL, y = 0, z = 0, attributes = 0, links = { Link(2), Link(4), Link(5, 2 * CELL) } },
		[4] = { x = 3 * CELL, y = 0, z = 0, attributes = 0, links = { Link(3) } },
		[5] = { x = CELL, y = CELL, z = 0, attributes = 0, links = { Link(1, 2 * CELL), Link(3, 2 * CELL) } },
	}
end

local function Request(fields)
	local request = {
		t = 1.5,
		source = "soldier",
		team = RED,
		start = 1,
		goal = 4,
		goalPos = { x = 3 * CELL, y = 0, z = 0 },
		strategy = "hl2",
		generation = 7,
		maxExpanded = Pathfinder.MAX_EXPANDED,
		limits = HL2.SOLDIER_LIMITS,
		bot = {
			entIndex = 12,
			now = 30,
			team = RED,
			route = TFBot.FASTEST_ROUTE,
			miniBoss = false,
			roundWon = false,
			winningTeam = 0,
			penalized = {},
		},
		blocked = {},
		uncrossable = {},
		rooms = {},
		estimates = {},
		result = nil,
	}
	for k, v in pairs(fields or {}) do request[k] = v end
	return request
end

local STRATEGIES = { hl2 = HL2 }

local function Joined(list) return table.concat(list, " ") end

T.test("a replayed search walks the recorded mesh", function()
	local record = { map = "test_row", areas = Mesh(), requests = { Request() } }
	local result = Record.Replay(record, record.requests[1], STRATEGIES)
	T.eq(result.status, Pathfinder.FOUND, "found")
	T.eq(Joined(result.route), "1 2 3 4", "straight along the row")
end)

T.test("an area the live search found closed is closed in the replay", function()
	local record = { map = "test_row", areas = Mesh(), requests = { Request({ blocked = { [2] = true } }) } }
	T.eq(Joined(Record.Replay(record, record.requests[1], STRATEGIES).route), "1 5 3 4", "round the blocked area")
end)

T.test("a link the live search could not cross is uncrossable in the replay", function()
	local request = Request({ uncrossable = { [2] = { [3] = true } } })
	local record = { map = "test_row", areas = Mesh(), requests = { request } }
	T.eq(Joined(Record.Replay(record, request, STRATEGIES).route), "1 5 3 4", "round the link")
end)

T.test("an enemy spawn room the live search saw is closed in the replay", function()
	local request = Request({ rooms = { [2] = BLUE } })
	local record = { map = "test_row", areas = Mesh(), requests = { request } }
	T.eq(Joined(Record.Replay(record, request, STRATEGIES).route), "1 5 3 4", "round the enemy's room")
end)

T.test("the replay uses the estimates the live search computed", function()
	local record = { map = "x", areas = Mesh(), requests = {} }
	local plain = Record.Replay(record, Request(), STRATEGIES)
	local steered = Record.Replay(record, Request({ estimates = { [2] = 1e6 } }), STRATEGIES)
	T.eq(Joined(plain.route), "1 2 3 4", "by the centres' distances")
	T.eq(Joined(steered.route), "1 5 3 4", "away from the area the recorded estimate overrates")
end)

T.test("a native replay does what the Lua replay does", function()
	local Native = T.native("wetsands").wetsands.navsearch
	local record = { map = "x", areas = Mesh(), requests = {} }
	for _, fields in ipairs({ {}, { blocked = { [2] = true } }, { uncrossable = { [3] = { [4] = true } } },
		{ rooms = { [2] = BLUE } }, { estimates = { [2] = 1e6 } }, { maxExpanded = 1 } }) do
		local lua = Record.Replay(record, Request(fields), STRATEGIES)
		local native = Record.Replay(record, Request(fields), STRATEGIES, Native)
		T.eq(Record.Matches(lua, native), true, "same search")
	end
end)

T.test("Matches says whether a replay did what the live search did", function()
	local request = Request()
	local record = { map = "test_row", areas = Mesh(), requests = { request } }
	local replayed = Record.Replay(record, request, STRATEGIES)
	request.result = {
		status = replayed.status,
		expanded = replayed.expanded,
		route = replayed.route,
	}
	T.eq(Record.Matches(request.result, replayed), true, "the same search")
	T.eq(Record.Matches({ status = replayed.status, expanded = replayed.expanded + 1, route = replayed.route }, replayed), false, "a different count")
	T.eq(Record.Matches({ status = replayed.status, expanded = replayed.expanded, route = { 1, 5, 3, 4 } }, replayed), false, "another route")
end)

T.test("a recording reads back as it was written", function()
	-- a link and a room the route never meets: the reverse of 3 -> 4, and
	-- RED's own room
	local request = Request({
		blocked = { [2] = true },
		uncrossable = { [4] = { [3] = true } },
		rooms = { [5] = RED },
		estimates = { [1] = 300, [2] = 200.25 },
	})
	request.bot.penalized = { [3] = true }
	local record = { map = "test_row", areas = Mesh(), requests = { request } }
	request.result = Record.Replay(record, request, STRATEGIES)
	local back = Record.Read(Record.Write(record))
	T.eq(back.map, "test_row", "the map")
	T.eq(back.areas[5].y, CELL, "an area's centre")
	T.eq(back.areas[1].links[2].to, 5, "its links, in order")
	T.eq(back.areas[1].links[2].distance, 2 * CELL, "with their lengths")
	local r = back.requests[1]
	T.eq(r.source .. " " .. r.team .. " " .. r.start .. " " .. r.goal .. " " .. r.generation, "soldier 2 1 4 7", "the request")
	T.eq(r.goalPos.x, 3 * CELL, "its goal position")
	T.eq(r.limits.jumpHeight, HL2.SOLDIER_JUMP_HEIGHT, "its limits")
	T.eq(r.limits.crouches, true, "crouching")
	T.eq(r.bot.route, TFBot.FASTEST_ROUTE, "its bot")
	T.eq(r.bot.penalized[3], true, "the penalized areas")
	T.eq(r.blocked[2], true, "the closed areas")
	T.eq(r.uncrossable[4][3], true, "the uncrossable links")
	T.eq(r.rooms[5], RED, "the spawn rooms")
	T.eq(r.estimates[2], 200.25, "the estimates")
	T.eq(Joined(r.result.route), "1 5 3 4", "and what it found")
	T.eq(Record.Matches(r.result, Record.Replay(back, r, STRATEGIES)), true, "replays as recorded")
end)

T.test("a request whose search had not finished reads back without a result", function()
	local back = Record.Read(Record.Write({ map = "x", areas = Mesh(), requests = { Request() } }))
	T.eq(back.requests[1].result, nil, "no result")
end)

T.test("a recording in another format is refused", function()
	T.eq(pcall(Record.Read, "not a recording"), false, "refused")
end)

T.finish()
