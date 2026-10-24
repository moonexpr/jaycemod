-- games.nextsoldier.reach_memo: the regions failed route searches walked to
-- the end, kept so a goal outside one is known out of reach without a
-- search.
local T = dofile("tests/harness.lua")
local ReachMemo = nextsoldier.reach_memo
local Expiring = cache.expiring
local Class = core.class
local HL2 = T.require("foundation.wetsands.path.hl2")
local TFBot = T.require("foundation.wetsands.path.tfbot")

local RED, BLUE = 2, 3
local TERM = 30
local GENERATION = 3

local function Clock()
	local clock = { now = 0 }
	function clock:Now() return self.now end
	return clock
end

local function Memo(clock)
	return ReachMemo.New({
		clock = clock or Clock(),
		term = TERM,
		capacity = 8,
	})
end

local function Request(bot)
	local b = {
		team = RED,
		route = TFBot.FASTEST_ROUTE,
		roundWon = false,
		winningTeam = 0,
	}
	for k, v in pairs(bot or {}) do b[k] = v end
	return {
		strategy = HL2,
		limits = HL2.SOLDIER_LIMITS,
		bot = b,
	}
end

-- The search from 1 reached 1, 2, 3 (1 -> 2 -> 3), and was turned back at
-- 4 (closed to it) and over the link 3 -> 5.
local function Walked()
	return ReachMemo.Region(1, { [2] = 1, [3] = 2 }, { [4] = true }, { [3] = { [5] = true } })
end

local OPEN = function() return true end
local CLOSED = function() return false end
-- whether every change since a generation is one a region's refusals catch
local KNOWN = function() return true end

local function Joined(list) return table.concat(list, " ") end

T.test("a reach memo is an expiring cache", function()
	T.eq(Class.IsA(Memo(), Expiring.Expiring), true, "of the base")
end)

T.test("a region holds the areas its search reached", function()
	local region = Walked()
	T.eq(region[1], true, "its start")
	T.eq(region[3], true, "an area reached")
	T.eq(region[4], false, "one turned back from")
	T.eq(region:Size(), 3, "three")
	T.eq(Joined(region:RouteTo(3)), "1 2 3", "the way from its start, as its search went")
end)

T.test("a region's nearest area to a goal is the one with the least distance", function()
	local centers = { [1] = { x = 0, y = 0, z = 0 }, [2] = { x = 100, y = 0, z = 0 }, [3] = { x = 100, y = 100, z = 0 } }
	T.eq(Walked():Nearest({ x = 200, y = 0, z = 0 }, function(id) return centers[id] end), 2, "the nearest")
end)

T.test("reachability keys ignore who asks, the spread of routes and penalties", function()
	local memo = Memo()
	local key = memo:Key(Request())
	T.eq(key, memo:Key(Request({ route = TFBot.DEFAULT_ROUTE, entIndex = 4, now = 9 })), "a bot's own spread")
	T.eq(key, memo:Key(Request({ penalized = { [7] = true } })), "a lane's penalties")
	T.eq(key == memo:Key(Request({ team = BLUE })), false, "another team")
	T.eq(key == memo:Key(Request({ roundWon = true, winningTeam = RED })), false, "once the round is won")
end)

T.test("a region outlasts blocker changes its refusals catch, not changes of unknown extent", function()
	local memo = Memo()
	local key = memo:Key(Request())
	memo:Learn(key, Walked(), GENERATION)
	local asked
	local function Known(generation)
		asked = generation
		return true
	end
	T.eq(memo:Unreachable(key, 1, 9, CLOSED, CLOSED, GENERATION + 2, Known) ~= nil, true, "after doors moved elsewhere")
	T.eq(asked, GENERATION, "asked about the changes since it was learned")
	T.eq(memo:Unreachable(key, 1, 9, CLOSED, CLOSED, GENERATION + 2, function() return false end), nil, "after the mesh's links changed")
end)

T.test("a goal outside a region its start lies in is out of reach while the region's edges hold", function()
	local memo = Memo()
	local key = memo:Key(Request())
	memo:Learn(key, Walked(), GENERATION)
	local region = memo:Unreachable(key, 2, 9, CLOSED, CLOSED, GENERATION, KNOWN)
	T.eq(region and region.start, 1, "from inside it")
	T.eq(memo:Unreachable(key, 2, 3, CLOSED, CLOSED, GENERATION, KNOWN), nil, "a goal inside it is not")
	T.eq(memo:Unreachable(key, 8, 9, CLOSED, CLOSED, GENERATION, KNOWN), nil, "nor is a start outside it known")
end)

T.test("a region whose edges opened since is no proof", function()
	local memo = Memo()
	local key = memo:Key(Request())
	memo:Learn(key, Walked(), GENERATION)
	T.eq(memo:Unreachable(key, 1, 9, function(id) return id == 4 end, CLOSED, GENERATION, KNOWN), nil, "the closed area opened")
	T.eq(memo:Unreachable(key, 1, 9, CLOSED, OPEN, GENERATION, KNOWN), nil, "the refused link opened")
	T.eq(memo:Unreachable(key, 1, 9, CLOSED, CLOSED, GENERATION, KNOWN) ~= nil, true, "still closed")
end)

T.test("a region lasts the memo's term", function()
	local clock = Clock()
	local memo = Memo(clock)
	local key = memo:Key(Request())
	memo:Learn(key, Walked(), GENERATION)
	clock.now = TERM + 1
	T.eq(memo:Unreachable(key, 1, 9, CLOSED, CLOSED, GENERATION, KNOWN), nil, "forgotten")
end)

T.test("a key keeps its newest regions", function()
	local memo = Memo()
	local key = memo:Key(Request())
	for start = 100, 100 + ReachMemo.REGIONS_PER_KEY do memo:Learn(key, ReachMemo.Region(start, {}, {}, {}), GENERATION) end
	T.eq(memo:Unreachable(key, 100, 9, CLOSED, CLOSED, GENERATION, KNOWN), nil, "the oldest dropped")
	T.eq(memo:Unreachable(key, 100 + ReachMemo.REGIONS_PER_KEY, 9, CLOSED, CLOSED, GENERATION, KNOWN) ~= nil, true, "the newest kept")
end)

T.finish()
