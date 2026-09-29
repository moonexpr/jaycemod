-- foundation.npc.debug: the NextBot debug layer's rules (wetsand_nb_debug,
-- after the engine's nb_ commands).
local T = dofile("tests/harness.lua")
local Debug = T.require("foundation.npc.debug")
local N = T.require("foundation.npc")
local Path = T.require("foundation.npc.path")

local function V(x, y, z)
	return {
		x = x,
		y = y,
		z = z,
	}
end

local function Names(layers)
	return table.concat(Debug.LayerNames(layers), " ")
end

local ZOMBIE = {
	key = "zombie",
	index = 45,
	class = "tf_zombie",
	variant = "foundation.npc.zombie",
}
local HATMAN = {
	key = "hatman",
	index = 46,
	class = "headless_hatman",
	variant = "foundation.npc.hatman",
}

-- Layers (nb_debug)

T.test("a layer named on the command line toggles, by any prefix, in any case", function()
	local layers = Debug.ParseLayers({}, { "path", "BEH" })
	T.eq(Names(layers), Debug.PATH .. " " .. Debug.BEHAVIOR, "both on")
	layers = Debug.ParseLayers(layers, { "Path", "cost" })
	T.eq(Names(layers), Debug.COST .. " " .. Debug.BEHAVIOR, "path off, cost on")
end)

T.test("ALL or * turns every layer on, OFF or no argument every layer off", function()
	T.eq(#Debug.LayerNames(Debug.ParseLayers({}, { "all" })), #Debug.LAYERS, "all")
	T.eq(#Debug.LayerNames(Debug.ParseLayers({}, { "*" })), #Debug.LAYERS, "star")
	local on = Debug.ParseLayers({}, { "all" })
	T.eq(Names(Debug.ParseLayers(on, { "off" })), "", "off")
	T.eq(Names(Debug.ParseLayers(on, {})), "", "no argument")
	T.eq(Debug.DescribeLayers(Debug.ParseLayers(on, {})), "off", "described")
end)

T.test("an unknown layer is reported and changes nothing", function()
	local layers, unknown = Debug.ParseLayers({ [Debug.NAV] = true }, { "vision", "nav" })
	T.eq(#unknown, 1, "one unknown")
	T.eq(unknown[1], "vision", "named")
	T.eq(Names(layers), "", "nav toggled off, nothing else")
end)

T.test("parsing leaves the layers it was given alone", function()
	local current = { [Debug.PATH] = true }
	Debug.ParseLayers(current, { "path" })
	T.eq(current[Debug.PATH], true, "unchanged")
end)

-- The filter (nb_debug_filter)

T.test("an empty filter lets every NPC through", function()
	T.eq(Debug.FilterMatches(Debug.ParseFilter(Debug.NewFilter(), {}), ZOMBIE), true, "all")
end)

T.test("a filter adds entity indexes and names, which match a class or variant by prefix, in any case", function()
	local filter = Debug.ParseFilter(Debug.NewFilter(), { "46" })
	T.eq(Debug.FilterMatches(filter, HATMAN), true, "by index")
	T.eq(Debug.FilterMatches(filter, ZOMBIE), false, "another index")
	filter = Debug.ParseFilter(filter, { "TF_Z" })
	T.eq(Debug.FilterMatches(filter, ZOMBIE), true, "by class, added to the index")
	T.eq(Debug.FilterMatches(Debug.ParseFilter(Debug.NewFilter(), { "zomb" }), ZOMBIE), true, "by the variant's own name")
	T.eq(Debug.FilterMatches(Debug.ParseFilter(Debug.NewFilter(), { "foundation.npc.hat" }), HATMAN), true, "by the variant's full name")
	T.eq(Debug.FilterMatches(Debug.ParseFilter(Debug.NewFilter(), { "hat" }), ZOMBIE), false, "no match")
end)

T.test("no arguments clear the filter", function()
	local filter = Debug.ParseFilter(Debug.NewFilter(), { "46" })
	T.eq(Debug.FilterMatches(Debug.ParseFilter(filter, {}), ZOMBIE), true, "cleared")
	T.eq(Debug.DescribeFilter(Debug.ParseFilter(filter, {})), "none (every NPC)", "described")
	T.eq(Debug.DescribeFilter(Debug.ParseFilter(filter, { "zomb" })), "#46 zomb", "listed")
end)

T.test("zero is a name, not an index, as nb_debug_filter reads it", function()
	local filter = Debug.ParseFilter(Debug.NewFilter(), { "0" })
	T.eq(Debug.FilterMatches(filter, { key = 1, index = 0, class = "x", variant = "" }), false, "no index 0")
end)

-- Selection (nb_select)

T.test("the NPC picked is the nearest live one within the crosshair's cone", function()
	local eye, forward = V(0, 0, 0), V(1, 0, 0)
	local far = { center = V(100, 0, 0), alive = true }
	local near = { center = V(50, 1, 0), alive = true }
	local dead = { center = V(10, 0, 0), alive = false }
	local aside = { center = V(0, 100, 0), alive = true }
	T.eq(Debug.Pick(eye, forward, { far, near, dead, aside }), near, "nearest live in the cone")
	T.eq(Debug.Pick(eye, forward, { aside }), nil, "nothing in the cone")
	T.eq(Debug.Pick(eye, forward, {}), nil, "no NPCs")
end)

-- Subscriptions: what each admin sees

T.test("with no selection an admin sees every NPC the filter passes; with one, only it", function()
	local sub = Debug.NewSubscription()
	sub:SetLayers({ "path" })
	sub:SetFilter({ "tf_" })
	T.eq(sub:Wants(ZOMBIE, Debug.PATH), true, "filtered in")
	T.eq(sub:Wants(HATMAN, Debug.PATH), false, "filtered out")
	sub:Select(HATMAN.key)
	T.eq(sub:Wants(HATMAN, Debug.PATH), true, "the selected, whatever the filter")
	T.eq(sub:Wants(ZOMBIE, Debug.PATH), false, "only the selected")
	sub:Select(nil)
	T.eq(sub:Wants(ZOMBIE, Debug.PATH), true, "selection cleared")
end)

T.test("COST and NAV are drawn for the selected NPC only", function()
	local sub = Debug.NewSubscription()
	sub:SetLayers({ "all" })
	T.eq(sub:Wants(ZOMBIE, Debug.COST), false, "no selection, no cost")
	T.eq(sub:Wants(ZOMBIE, Debug.NAV), false, "no selection, no nav")
	T.eq(sub:Wants(ZOMBIE, Debug.BEHAVIOR), true, "behavior for all")
	sub:Select(ZOMBIE.key)
	T.eq(sub:Wants(ZOMBIE, Debug.COST), true, "selected: cost")
	T.eq(sub:Wants(ZOMBIE, Debug.NAV), true, "selected: nav")
end)

T.test("a removed NPC is no longer selected", function()
	local sub = Debug.NewSubscription()
	sub:Select(ZOMBIE.key)
	sub:Forget(HATMAN.key)
	T.eq(sub.selected, ZOMBIE.key, "another NPC's removal")
	sub:Forget(ZOMBIE.key)
	T.eq(sub.selected, nil, "its own")
end)

T.test("an NPC's paths are watched only while someone draws them, and its costs only while selected", function()
	local drawer, selector = Debug.NewSubscription(), Debug.NewSubscription()
	T.eq(Debug.PathWatch({ drawer, selector }, ZOMBIE), nil, "nobody asked")
	drawer:SetLayers({ "behavior" })
	T.eq(Debug.PathWatch({ drawer, selector }, ZOMBIE), nil, "behavior only")
	drawer:SetLayers({ "path" })
	T.eq(Debug.PathWatch({ drawer, selector }, ZOMBIE).costs, false, "drawn: the path, not the costs")
	selector:Select(ZOMBIE.key)
	T.eq(Debug.PathWatch({ drawer, selector }, ZOMBIE).costs, true, "selected: costs too, for the dump")
	T.eq(Debug.PathWatch({ drawer, selector }, HATMAN).costs, false, "the other NPC")
end)

T.test("an NPC's behavior is watched only while someone draws the BEHAVIOR layer for it", function()
	local sub = Debug.NewSubscription()
	T.eq(Debug.WatchesBehavior({ sub }, ZOMBIE), false, "off")
	sub:SetLayers({ "behavior" })
	T.eq(Debug.WatchesBehavior({ sub }, ZOMBIE), true, "on")
	sub:Select(HATMAN.key)
	T.eq(Debug.WatchesBehavior({ sub }, ZOMBIE), false, "another selected")
end)

T.test("a subscription is active while it shows a layer or holds a selection", function()
	local sub = Debug.NewSubscription()
	T.eq(sub:IsActive(), false, "new")
	sub:Select(ZOMBIE.key)
	T.eq(sub:IsActive(), true, "selection")
	sub:Select(nil)
	sub:SetLayers({ "nav" })
	T.eq(sub:IsActive(), true, "layer")
end)

-- The cost recorder (COST)

T.test("the recorder keeps each area's cheapest cost so far, and an area impassable from every side as impassable", function()
	local recorder = Debug.NewCostRecorder()
	recorder:Record(1, nil, 0)
	recorder:Record(2, 1, 100)
	recorder:Record(3, 1, Path.IMPASSABLE)
	recorder:Record(4, 1, Path.IMPASSABLE)
	recorder:Record(2, 4, 80)
	recorder:Record(4, 2, 150)
	local explored = recorder:Explored()
	T.eq(#explored, 4, "four areas")
	local summary = {}
	for i, area in ipairs(explored) do
		summary[i] = area.id .. "=" .. (area.impassable and "x" or area.cost)
	end
	T.eq(table.concat(summary, " "), "1=0 2=80 4=150 3=x", "cheapest first, impassable last")
	T.eq(recorder:Expanded(), 3, "three areas were expanded from")
end)

T.test("decimating keeps the path's areas and a spread of the rest across the cost range", function()
	local explored = {}
	for i = 1, 10 do explored[i] = { id = i, cost = i * 10, impassable = false } end
	local kept, dropped = Debug.Decimate(explored, { 7, 9 }, 5)
	T.eq(#kept, 5, "the limit")
	T.eq(dropped, 5, "the rest dropped")
	local ids = {}
	for _, area in ipairs(kept) do ids[area.id] = true end
	T.eq(ids[7] and ids[9], true, "the path's areas")
	T.eq(ids[1], true, "the cheapest")
	local all, none = Debug.Decimate(explored, {}, 20)
	T.eq(#all .. " " .. none, "10 0", "under the limit, all kept")
end)

T.test("the net budget allows at least a few hundred areas", function()
	T.eq(Debug.MAX_COST_AREAS >= 500, true, "room")
	T.eq(Debug.MAX_COST_AREAS * Debug.COST_AREA_BYTES <= Debug.NET_BUDGET_BYTES, true, "within the budget")
end)

T.test("the cost ramp runs from its first colour to its last, and ignores impassable areas for its range", function()
	local areas = {
		{ id = 1, cost = 10, impassable = false },
		{ id = 2, cost = 110, impassable = false },
		{ id = 3, cost = Path.IMPASSABLE, impassable = true },
	}
	local lo, hi = Debug.CostRange(areas)
	T.eq(lo .. " " .. hi, "10 110", "range")
	local first, last = Debug.COST_RAMP[1], Debug.COST_RAMP[#Debug.COST_RAMP]
	local r, g, b = Debug.CostColor(10, lo, hi)
	T.eq(r .. " " .. g .. " " .. b, first[1] .. " " .. first[2] .. " " .. first[3], "cheapest")
	r, g, b = Debug.CostColor(110, lo, hi)
	T.eq(r .. " " .. g .. " " .. b, last[1] .. " " .. last[2] .. " " .. last[3], "dearest")
	r = Debug.CostColor(500, lo, hi)
	T.eq(r, last[1], "clamped")
	r = Debug.CostColor(5, 5, 5)
	T.eq(r, first[1], "an empty range")
end)

-- Path reports (PATH)

-- overrides: fields to change; without: names of fields to leave out.
local function Report(overrides, without)
	local fields = {
		source = Debug.SOURCE_ENGINE,
		strategy = "foundation.npc.path.scatter",
		start = V(0, 0, 0),
		goal = V(300, 0, 0),
		limits = {
			stepHeight = 18,
			jumpHeight = 72,
		},
		found = true,
		points = {
			{ pos = V(0, 0, 0), move = Debug.MOVE_GROUND },
			{ pos = V(300, 0, 0), move = Debug.MOVE_JUMP },
		},
		areaIds = { 1, 2 },
		totalCost = 1234.4,
		microseconds = 420,
		nodesExpanded = 12,
		explored = {
			{ id = 1, cost = 0, impassable = false },
		},
		computedAt = 10,
	}
	for k, v in pairs(overrides or {}) do fields[k] = v end
	for _, name in ipairs(without or {}) do fields[name] = nil end
	return fields
end

T.test("a segment's type becomes the move it is drawn as, as Path::Draw colours them", function()
	T.eq(Debug.MoveOfSegment(Debug.SEGMENT_ON_GROUND), Debug.MOVE_GROUND, "ground")
	T.eq(Debug.MoveOfSegment(Debug.SEGMENT_DROP_DOWN), Debug.MOVE_DROP, "drop")
	T.eq(Debug.MoveOfSegment(Debug.SEGMENT_CLIMB_UP), Debug.MOVE_CLIMB, "climb")
	T.eq(Debug.MoveOfSegment(Debug.SEGMENT_JUMP_OVER_GAP), Debug.MOVE_JUMP, "jump")
	T.eq(Debug.MoveOfSegment(Debug.SEGMENT_LADDER_UP), Debug.MOVE_LADDER, "ladder up")
	T.eq(Debug.MoveOfSegment(Debug.SEGMENT_LADDER_DOWN), Debug.MOVE_LADDER, "ladder down")
	for _, move in ipairs({ Debug.MOVE_GROUND, Debug.MOVE_DROP, Debug.MOVE_CLIMB, Debug.MOVE_JUMP, Debug.MOVE_LADDER }) do
		T.eq(type(Debug.MOVE_COLORS[move]), "table", "a colour for " .. Debug.MOVE_NAMES[move])
	end
end)

T.test("a path report needs what was asked and what came of it", function()
	local report = Debug.NewPathReport(Report())
	T.eq(report.totalCost, 1234.4, "kept")
	local ok, err = pcall(Debug.NewPathReport, Report({ microseconds = "fast" }))
	T.eq(ok, false, "a bad field is refused")
	T.eq(tostring(err):find("microseconds", 1, true) ~= nil, true, "named: " .. tostring(err))
	ok = pcall(Debug.NewPathReport, Report({}, { "points" }))
	T.eq(ok, false, "a missing field is refused")
	T.eq(Debug.NewPathReport(Report({}, { "totalCost", "nodesExpanded", "explored" })).explored, nil, "the optional ones may be absent")
end)

T.test("a path's summary gives the strategy, the outcome, the cost, the search's time and the path's age", function()
	local lines = Debug.PathLines(Debug.NewPathReport(Report()), 13.5)
	T.eq(lines[1], "Path: foundation.npc.path.scatter (" .. Debug.SOURCE_ENGINE .. ")", "strategy")
	T.eq(lines[2], "Found: 2 points, cost 1234", "outcome")
	T.eq(lines[3], "Search: 0.42 ms, 12 areas expanded", "search")
	T.eq(lines[4], "Age: 3.5 s", "age")
	lines = Debug.PathLines(Debug.NewPathReport(Report({ found = false }, { "totalCost", "nodesExpanded" })), 10)
	T.eq(lines[2], "Goal out of reach, to the closest area: 2 points, cost ?", "not found")
	T.eq(lines[3], "Search: 0.42 ms, ? areas expanded", "unknown expansions")
end)

-- The behavior log (BEHAVIOR)

local function Clock(now)
	return { now = now, Now = function(self) return self.now end }
end

T.test("the behavior log words each change as nb_debug BEHAVIOR does, and keeps the last few", function()
	local clock = Clock(1)
	local log = Debug.NewBehaviorLog(clock, 3)
	log:Transition(N.CHANGE_TO, "Chase", "Chase", "Starting Action", true)
	log:Transition(N.CHANGE_TO, "Chase", "Attack", "in range", false)
	log:Transition(N.SUSPEND_FOR, "Attack", "Flinch", nil, false)
	log:Transition(N.DONE, "Flinch", nil, "recovered", false)
	local entries = log:Entries()
	T.eq(#entries, 3, "the capacity")
	T.eq(entries[1].text, "Chase CHANGE_TO Attack: in range", "change")
	T.eq(entries[2].text, "Attack SUSPEND_FOR Flinch", "suspension without a reason")
	T.eq(entries[3].text, "Flinch DONE: recovered", "done")
	log:Transition(N.CHANGE_TO, "Idle", "Idle", "Starting Action", true)
	T.eq(log:Entries()[3].text, "STARTING Idle", "a start")
end)

T.test("a repeated event is counted, not listed again", function()
	local clock = Clock(1)
	local log = Debug.NewBehaviorLog(clock, 3)
	log:Event("OnNavAreaChanged")
	clock.now = 2
	log:Event("OnNavAreaChanged")
	log:Event("OnNavAreaChanged")
	local entries = log:Entries()
	T.eq(#entries, 1, "one entry")
	T.eq(entries[1].text, "EVENT OnNavAreaChanged x3", "counted")
	T.eq(entries[1].time, 2, "the latest time")
end)

T.test("a watched Behavior's lines give its stack, outermost first, then its recent changes, as a scenario", function()
	local clock = Clock(5)
	local Attack = N.Action:Extend("Attack")
	local Chase = N.Action:Extend("Chase")
	function Chase:Update(me) return self:ChangeTo(Attack:New(), "in range") end
	local Main = N.Action:Extend("ZombieBehavior")
	function Main:InitialContainedAction(me) return Chase:New() end
	local behavior = N.Behavior:New(Main:New(), "zombie")
	local log = Debug.NewBehaviorLog(clock, Debug.BEHAVIOR_LOG_SIZE)
	behavior:Watch(log)
	behavior:Update(clock, 0.1)
	clock.now = 6
	behavior:Update(clock, 0.1)
	behavior:Event(clock, "OnInjured")
	clock.now = 7
	local lines = Debug.BehaviorLines("zombie", behavior:Stack(), log:Entries(), clock:Now())
	T.eq(table.concat(lines, "|"), table.concat({
		"Behavior: zombie",
		"  ZombieBehavior",
		"    Attack",
		"Recent:",
		"  -2.0 s STARTING ZombieBehavior",
		"  -2.0 s STARTING Chase",
		"  -1.0 s Chase CHANGE_TO Attack: in range",
		"  -1.0 s EVENT OnInjured",
	}, "|"), "lines")
end)

T.test("a suspended action is marked in the stack's lines", function()
	local lines = Debug.BehaviorLines("x", {
		{ name = "Flinch", depth = 1, suspended = false },
		{ name = "Chase", depth = 1, suspended = true },
	}, {}, 0)
	T.eq(lines[3], "  Chase (suspended)", "marked")
	T.eq(#lines, 3, "no recent section without entries")
end)

-- NAV

T.test("the nearest nav areas come first, up to the limit", function()
	local items = { { id = 1, distance = 30 }, { id = 2, distance = 10 }, { id = 3, distance = 20 } }
	local nearest = Debug.NearestFirst(items, 2)
	T.eq(#nearest .. " " .. nearest[1].id .. " " .. nearest[2].id, "2 2 3", "two nearest")
end)

T.test("a nav area's label is its id, then any attributes the sidecar gives", function()
	T.eq(Debug.NavLabel(812, {}), "#812", "bare")
	T.eq(Debug.NavLabel(812, { "BLUE_SPAWN_ROOM", "NO_SPAWNING" }), "#812 BLUE_SPAWN_ROOM NO_SPAWNING", "with attributes")
end)

-- The dump (wetsand_nb_dump)

T.test("a dump is named for the map, the NPC and the time, under the data folder's wetsand_nb", function()
	T.eq(Debug.DumpPath("plr_hightower", 45, 1700000000), Debug.DUMP_DIR .. "/plr_hightower_45_1700000000.json", "path")
end)

T.test("a dump holds the request, the result, the explored areas and the timing as plain values", function()
	local doc = Debug.DumpDocument({
		map = "plr_hightower",
		index = 45,
		class = "tf_zombie",
		variant = "foundation.npc.zombie",
	}, Debug.NewPathReport(Report()))
	T.eq(doc.map, "plr_hightower", "map")
	T.eq(doc.npc.index, 45, "npc")
	T.eq(doc.request.goal.x, 300, "goal as a plain point")
	T.eq(doc.request.strategy, "foundation.npc.path.scatter", "strategy")
	T.eq(doc.request.limits.jumpHeight, 72, "limits")
	T.eq(doc.result.points[2].move, Debug.MOVE_NAMES[Debug.MOVE_JUMP], "moves by name")
	T.eq(doc.result.totalCost, 1234.4, "cost")
	T.eq(doc.search.microseconds, 420, "timing")
	T.eq(doc.search.explored[1].id, 1, "explored")
	T.eq(doc.search.costsRecorded, true, "recorded")
	local bare = Debug.DumpDocument({ map = "m", index = 1, class = "c", variant = "v" }, Debug.NewPathReport(Report({}, { "explored" })))
	T.eq(#bare.search.explored .. " " .. tostring(bare.search.costsRecorded), "0 false", "no costs recorded")
end)

T.finish()
