-- features.aiwar.inspect: NextSoldier's squads, lanes and battle lines as
-- the debugging commands and the overlay tell them.
local T = dofile("tests/harness.lua")
local Inspect = T.require("features.aiwar.inspect")
local Tactics = T.require("games.nextsoldier.tactics")
local Orders = T.require("features.aiwar.orders")

local RED, BLUE = 2, 3

local function P(x, y) return { x = x, y = y, z = 0 } end

local function Has(text, fragment, what)
	T.eq(text:find(fragment, 1, true) ~= nil, true, (what or fragment) .. " in: " .. text)
end

local function Lacks(text, fragment, what)
	T.eq(text:find(fragment, 1, true) == nil, true, (what or fragment) .. " not in: " .. text)
end

-- A fire team of the given members, placed in order; the first is oldest
-- and so leads.
local function Squad(role, index, ...)
	local fireTeam = {
		team = BLUE,
		role = role,
		index = index,
		members = {},
	}
	local members = {}
	for place, pos in ipairs({ ... }) do
		local member = {
			place = place - 1,
			seq = place,
			pos = pos,
			fireTeam = fireTeam,
			label = "#" .. (40 + place),
		}
		fireTeam.members[place - 1] = member
		members[place] = member
	end
	return fireTeam, members
end

local function Describe(member) return member.label, member.doing end

-- Squads -------------------------------------------------------------------------

T.test("a squad's summary names it, counts it and says it has no contact", function()
	local fireTeam, members = Squad("escort", 2, P(0, 0), P(100, 0))
	local summary = Inspect.Summary(fireTeam, members, 10)
	Has(summary, "escort 2")
	Has(summary, "2 strong")
	Has(summary, "no contact")
end)

T.test("a bounding squad tells which element moves, how many are there and when it swaps", function()
	local fireTeam, members = Squad("escort", 1, P(0, 0), P(100, 0), P(200, 0), P(300, 0))
	Tactics.Report(fireTeam, P(900, 0), 10)
	Tactics.Bound(fireTeam, 10)
	Tactics.Arrived(fireTeam, members[1])
	local summary = Inspect.Summary(fireTeam, members, 12)
	Has(summary, "contact 2 s ago")
	Has(summary, "element 0 moving, 1 of 2 there")
	Has(summary, "swaps in " .. (Tactics.BOUND_TIME - 2) .. " s")
end)

T.test("a flanking squad says to which side, and that it is done", function()
	local fireTeam, members = Squad("raid", 1, P(0, 0))
	fireTeam.flank = P(500, 500)
	Has(Inspect.Summary(fireTeam, members, 0), "flanking left", "raid 1 flanks to the left (FlankSide 1)")
	fireTeam.index = 3
	Has(Inspect.Summary(fireTeam, members, 0), "flanking right")
	fireTeam.flankDone = true
	Has(Inspect.Summary(fireTeam, members, 0), "flanked")
end)

T.test("a squad falling back tells its steps, and its lane when it holds one", function()
	local fireTeam, members = Squad("defend", 1, P(0, 0))
	Tactics.FallBack(fireTeam, 5)
	fireTeam.laneIndex = 2
	local summary = Inspect.Summary(fireTeam, members, 6)
	Has(summary, "fell back 1 of " .. Tactics.FALLBACK_STEPS .. " steps")
	Has(summary, "lane 2")
end)

T.test("a squad's report lists its leader, then each member's distance from it, and flags stragglers", function()
	local far = Orders.REGROUP_RANGE + 100
	local fireTeam, members = Squad("escort", 2, P(0, 0), P(0, 250), P(far, 0))
	members[1].doing, members[2].doing, members[3].doing = "bounding", "overwatch", "regrouping on its leader"
	local lines = Inspect.SquadLines(fireTeam, members, 0, Describe)
	T.eq(#lines, 4, "a heading and one line per member")
	Has(lines[1], "escort 2")
	Has(lines[1], "led by #41")
	Has(lines[1], "spread " .. far .. " u")
	Has(lines[2], "place 0 #41 leads: bounding")
	Has(lines[3], "place 1 #42: 250 u from its leader, overwatch")
	Lacks(lines[3], "straggling")
	Has(lines[4], "straggling")
end)

T.test("a member whose orders have not placed it yet is reported without a distance", function()
	local fireTeam, members = Squad("escort", 1, P(0, 0), P(100, 0))
	members[2].pos = nil
	local lines = Inspect.SquadLines(fireTeam, members, 0, Describe)
	Has(lines[1], "spread 0 u")
	Has(lines[3], "place 1 #42: no position yet")
	members[1].pos = nil
	Has(Inspect.SquadLines(fireTeam, members, 0, Describe)[3], "no position yet")
end)

T.test("a hero leads its squad in the report whatever its place", function()
	local fireTeam, members = Squad("escort", 1, P(0, 0), P(100, 0))
	members[2].hero = true
	local lines = Inspect.SquadLines(fireTeam, members, 0, Describe)
	Has(lines[1], "led by #42 (hero)")
	Has(lines[3], "place 1 #42 leads")
end)

-- Lanes ------------------------------------------------------------------------

local function Lane(ids, length, count, kind)
	local points = {}
	for i = 1, count or 2 do points[i] = P(i * 100, 0) end
	return {
		kind = kind or "direct",
		ids = ids,
		points = points,
		length = length,
	}
end

local function Holding(role, index, lanes, laneIndex, team)
	return {
		team = team or BLUE,
		role = role,
		index = index,
		laneKey = lanes.key,
		laneIndex = laneIndex,
	}
end

T.test("a team's lanes are told by kind, length and who holds them", function()
	local lanes = { key = "3:10", Lane({ 1, 2, 3, 4 }, 1000, 5), Lane({ 1, 5, 6, 7 }, 1500, 7, "tour") }
	local fireTeams = {
		Holding("escort", 1, lanes, 1),
		Holding("raid", 1, lanes, 2),
		Holding("escort", 2, lanes, 1),
		Holding("escort", 3, lanes, 2, RED),
		Holding("assault", 4, { key = "old" }, 2),
	}
	local lines = Inspect.LaneLines(lanes, fireTeams, BLUE, nil, 0)
	T.eq(#lines, 2, "one line per lane")
	Has(lines[1], "lane 1 (direct): 1000 u, 5 waypoints")
	Has(lines[1], "held by escort 1, escort 2")
	Has(lines[2], "lane 2 (tour): 1500 u, 7 waypoints")
	Has(lines[2], "held by raid 1")
	Lacks(lines[2], "escort 3", "the other team's squad")
	Lacks(lines[2], "assault 4", "a squad holding the last plan's lane")
end)

T.test("a lane no squad holds says so, and its label names its holders", function()
	local lanes = { key = "k", Lane({ 1 }, 800), Lane({ 2 }, 900, 2, "tour") }
	local fireTeams = { Holding("raid", 2, lanes, 2) }
	Has(Inspect.LaneLines(lanes, fireTeams, BLUE, nil, 0)[1], "held by no squad")
	T.eq(Inspect.LaneLabel(lanes, 2, fireTeams, BLUE), "lane 2 (tour): 900 u, raid 2")
	T.eq(Inspect.LaneLabel(lanes, 1, fireTeams, BLUE), "lane 1 (direct): 800 u")
end)

T.test("a team without lanes says why: planning, or waiting to try again", function()
	local planning = Inspect.LaneLines(nil, {}, BLUE, { planning = true, tries = 2, specs = { {}, {}, {}, {}, {} } }, 0)
	Has(planning[1], "no lanes")
	Has(planning[2], "planning: lane 2 of 5")
	local waiting = Inspect.LaneLines(nil, {}, BLUE, { planning = false, tries = 1, retryAt = 14 }, 10)
	Has(waiting[2], "no route found; trying again in 4 s")
	T.eq(#Inspect.LaneLines(nil, {}, BLUE, nil, 0), 1, "never planned: only that it has none")
end)

-- Battle lines --------------------------------------------------------------------

T.test("a line facing the enemy runs across its facing, side to side, with its width and depth", function()
	-- facing +x: the line runs along y
	local shape = Inspect.Shape({ P(0, 300), P(50, -300), P(-20, 0) }, P(1, 0))
	T.eq(shape.closed, false, "a line, not a ring")
	T.eq(#shape.points, 3, "every post")
	T.eq(shape.points[1].y, 300, "from the left of the facing")
	T.eq(shape.points[2].y, 0, "through the middle")
	T.eq(shape.points[3].y, -300, "to the right")
	T.near(shape.width, 600, 1e-9, "side to side")
	T.near(shape.depth, 70, 1e-9, "front to back")
end)

T.test("posts held all round (no facing) make a ring, ordered round its centre", function()
	local shape = Inspect.Shape({ P(100, 0), P(-100, 0), P(0, 100), P(0, -100) }, nil)
	T.eq(shape.closed, true, "a ring")
	local order = {}
	for i, p in ipairs(shape.points) do order[i] = p.x .. "," .. p.y end
	T.eq(table.concat(order, " "), "0,-100 100,0 0,100 -100,0", "by angle round the centre")
	T.near(shape.width, 200, 1e-9, "across")
end)

T.test("a team's line faces away from its base, through the middle of its posts", function()
	local facing = Inspect.FacingFrom({ P(1000, 100), P(1000, -100) }, P(0, 0))
	T.eq(facing.x, 1000, "out from the base")
	T.eq(facing.y, 0, "through the middle")
end)

T.test("a facing of no length is taken as all round", function()
	T.eq(Inspect.Shape({ P(0, 0), P(10, 0) }, P(0, 0)).closed, true, "a ring")
end)

T.test("a line's report counts its posts and gives its size", function()
	local line = Inspect.Shape({ P(0, 300), P(50, -300) }, P(1, 0))
	T.eq(Inspect.LineReport("guard posts", line), "guard posts: 2, 600 u wide and 50 u deep")
	local ring = Inspect.Shape({ P(100, 0), P(-100, 0) }, nil)
	T.eq(Inspect.LineReport("guard posts", ring), "guard posts: 2 all round, 200 u across")
	T.eq(Inspect.LineReport("forward posts", Inspect.Shape({}, P(1, 0))), "forward posts: none")
end)

T.finish()
