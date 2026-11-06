-- dev_3house's room-operations bench (.devtools/bin/dev_3house_map.py builds the map,
-- dev_3house_nav.lua its nav mesh): a squad of SIZE RED followers driven by their legs, feet free,
-- through a room operation, a stage at a time. Each stage is atomic: it removes the squad, sets
-- up its own start (where the members stand, the order they are on), acts, waits, and checks the
-- result as data, so any stage runs alone or all in turn.
--
--   spawn      at RED's spawns, at ease, in RED's spawn room
--   muster     from RED's spawns, mustered at its spawn room's middle: each given a place of its
--              own, spaced apart, its walk there crossing no other's, resting there, in the room
--   mobilize   out through RED's shutter to the staging point on the grass west of the bench
--   assault    from the staging point: staged around the bench's west door out of its sight, none
--              in before the leader's signal, then in, each at its place, spread over the room
--   hold       in the bench, alert: patrolling, none leaving the room
--   evacuate   in the bench, a danger marked at its east side (the war's DANGER mark, as the
--              Path Follower stool's Annotate places it): the leader calls the fall back, all
--              out of the room by a way away from it
--   rout       in the bench, half the squad killed: the leader calls the fall back, the rest leave
--   remuster   from outside the bench's west door to the rally point, each at its place
--
-- Load it, run a stage or all, then read the report:
--   python3 .devtools/bin/instances.py dev_3house - < .devtools/bin/dev_3house_bench.lua
--   python3 .devtools/bin/instances.py dev_3house 'return NSRoomBench.Run("evacuate")'
--   python3 .devtools/bin/instances.py dev_3house 'return NSRoomBench.RunAll()'
--   python3 .devtools/bin/instances.py dev_3house 'return NSRoomBench.Report()'
--   python3 .devtools/bin/instances.py dev_3house 'return NSRoomBench.Show("muster")'
local Legs = nextsoldier.behavior.group_identity
local Rooms = wartactics.rooms

local SIZE = 5
-- How near its spot a member has arrived, and how near the staging and rally points a squad
-- has gathered.
local ARRIVED, GATHERED = 96, 320
-- The staging point and the rally point: the grass west of the bench, beyond its west door.
local STAGING_OFFSET = Vector(-640, 0, 0)
-- Where members stand outside the bench's west door, evacuated, before they muster again.
local OUTSIDE_WEST = Vector(-520, 0, 0)
-- How much nearer than the squad's spacing two places may be: rounding.
local PLACE_SLACK = 1
-- How near the danger's spot its mark is taken after, and how many of the squad the rout kills.
local DANGER_UNMARK = 32
local ROUT_KILLS = 3

NSRoomBench = NSRoomBench or { results = {} }
local B = NSRoomBench

local function Named(name)
	local found = ents.FindByName(name)[1]
	if not IsValid(found) then error("dev_3house has no " .. name .. ": is this the map?", 2) end
	return found:GetPos()
end

local function Point(v) return { x = v.x, y = v.y, z = v.z } end

-- The ground under a spot, raised a hair so a body spawns on it.
local function Ground(v)
	local tr = util.TraceLine({ start = v + Vector(0, 0, 64), endpos = v - Vector(0, 0, 256), mask = MASK_NPCSOLID_BRUSHONLY })
	return tr.HitPos + Vector(0, 0, 1)
end

-- count spots spread round center, spacing apart, on the ground.
local function Around(center, count, spacing)
	local spots = {}
	for i = 1, count do
		local angle = (i - 1) / count * 2 * math.pi
		spots[i] = Ground(center + (i == 1 and vector_origin or Vector(math.cos(angle), math.sin(angle), 0) * spacing))
	end
	return spots
end

local function Clear()
	for _, member in ipairs(B.members or {}) do
		if IsValid(member) then member:Remove() end
	end
	B.members, B.order = {}, nil
end

local function Spawn(spots)
	Clear()
	for i, spot in ipairs(spots) do
		local member = ents.Create("npc_pathfollower")
		member.NSToolManaged = true
		member:SetPos(spot)
		member:Spawn()
		member:Activate()
		member:NSSetTeam(WS.TEAM_RED)
		member:NSSetDriver("legs")
		member:NSHoldFeet(false)
		B.members[i] = member
	end
end

local function Living()
	local living = {}
	for _, member in ipairs(B.members) do
		if IsValid(member) and member:Health() > 0 then living[#living + 1] = member end
	end
	return living
end

-- The squad given order, its places from where each stands, led by the first.
local function Give(order)
	local members = Living()
	local positions = {}
	for i, member in ipairs(members) do positions[i] = Point(member:GetPos()) end
	local at = Vector(order.point.x, order.point.y, order.point.z)
	local places = order:Places(positions, nextsoldier.engine.GroupSpacing(), members[1]:NSLegsAdmit(at),
		function(around) return members[1]:NSLegsAdmit(around) end)
	for i, member in ipairs(members) do member:NSLegsGive(order, places[i]) end
	order:Lead(members[1])
	B.order, B.starts, B.places = order, positions, places
	return order
end

-- The war's rooms on this map, found once.
local function RoomAt(pos)
	local controller = WS.Feature("aiwar")
	if not controller.rooms then controller:FindRoomsNow() end
	local area = navmesh.GetNearestNavArea(pos)
	return IsValid(area) and Rooms.RoomOf(controller.rooms, area:GetID()) or nil
end

local function InBench(member) return RoomAt(member:GetPos()) == RoomAt(Named("bench_room")) end

local function InSpawnRoom(member)
	local room = ents.FindByName("red_spawnroom")[1]
	local lo, hi = room:WorldSpaceAABB()
	return member:GetPos():WithinAABox(lo, hi + Vector(0, 0, 1))
end

local function Stack(member)
	local names = {}
	for i, frame in ipairs(nextsoldier.engine.Stack(member)) do names[i] = frame.name end
	return table.concat(names, " > ")
end

local function SpotOf(member) return member:GetNW2Vector("NSLegsSpot", member:GetPos()) end

-- What a check found: whether every condition held, and a line for each member.
local function Verdict(lines, failures)
	return { passed = #failures == 0, failures = failures, members = lines }
end

-- Each member's line, and a failure for each condition it fails (cond(member) -> ok, what).
local function Each(conditions)
	local lines, failures = {}, {}
	local members = Living()
	for i, member in ipairs(members) do
		local pos = member:GetPos()
		lines[i] = string.format("%d at %.0f,%.0f,%.0f, %.0f from its spot | %s", i, pos.x, pos.y, pos.z,
			pos:Distance2D(SpotOf(member)), Stack(member))
		for _, condition in ipairs(conditions) do
			local ok, what = condition(member)
			if not ok then failures[#failures + 1] = string.format("member %d: %s", i, what) end
		end
	end
	return lines, failures, members
end

local function Arrived(member) return member:GetPos():Distance2D(SpotOf(member)) <= ARRIVED, "not at its spot" end

local function Runs(action)
	return function(member) return Stack(member):find(action, 1, true) ~= nil, "not running " .. action end
end

local function Staging() return Named("bench_room") + STAGING_OFFSET end

-- Whether segments ab and cd cross, apart from touching or running along each other (a point
-- within ON_LINE of a line is on it: rounding).
local ON_LINE = 1e-6

local function Cross(a, b, c, d)
	local function Side(p, q, r)
		local side = (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
		return (side > ON_LINE and 1) or (side < -ON_LINE and -1) or 0
	end
	return Side(a, b, c) * Side(a, b, d) < 0 and Side(c, d, a) * Side(c, d, b) < 0
end

-- The places the squad was given, as failures: one left without, two nearer than its spacing,
-- two members' walks there crossing (not where they file through a doorway).
local function Placement(throughDoor)
	local failures, starts, places = {}, B.starts, B.places
	local spacing = nextsoldier.engine.GroupSpacing()
	for i = 1, #starts do
		if not places[i] then failures[#failures + 1] = string.format("member %d: no place", i) end
	end
	for i = 1, #starts do
		for j = i + 1, #starts do
			local a, b = places[i], places[j]
			if a and b then
				local apart = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
				if apart < spacing - PLACE_SLACK then
					failures[#failures + 1] = string.format("members %d and %d: places %.0f apart, under %.0f", i, j, apart, spacing)
				end
				if not throughDoor and Cross(starts[i], a, starts[j], b) then
					failures[#failures + 1] = string.format("members %d and %d: their walks cross", i, j)
				end
			end
		end
	end
	return failures
end

local function Resting(member) return member.NSStance ~= nil, "not resting at its place" end

-- How often an assault is watched: who is in the room before the signal, and who the room sees
-- while staged.
local WATCH_EVERY = 0.25

-- Watches the assault on room from now until its check: B.watch holds what it found.
local function WatchAssault(room, run)
	local watch = { early = {}, seen = {} }
	B.watch = watch
	local name = "dev_3house_bench_assault"
	timer.Create(name, WATCH_EVERY, 0, function()
		if run ~= B.runs or not B.order then timer.Remove(name) return end
		local order = B.order
		if order:Signalled() then
			if not watch.signalledAt then watch.signalledAt = CurTime() end
			return
		end
		for i, member in ipairs(B.members) do
			if IsValid(member) then
				if InBench(member) then watch.early[i] = true end
				if order:StagedAt(member) and room.seen(Point(member:GetPos())) then watch.seen[i] = true end
			end
		end
	end)
end

B.STAGES = {
	{
		name = "spawn",
		seconds = 2,
		setup = function()
			local spots = {}
			for i, spawn in ipairs(ents.FindByName("red_spawn")) do
				if i > SIZE then break end
				spots[i] = spawn:GetPos()
			end
			Spawn(spots)
		end,
		check = function()
			local lines, failures, members = Each({ function(m) return InSpawnRoom(m), "outside the spawn room" end,
				Runs("LegsAtEase") })
			if #members ~= SIZE then failures[#failures + 1] = #members .. " of " .. SIZE .. " spawned" end
			return Verdict(lines, failures)
		end,
	},
	{
		name = "muster",
		seconds = 10,
		setup = function()
			local spots = {}
			for i, spawn in ipairs(ents.FindByName("red_spawn")) do
				if i > SIZE then break end
				spots[i] = spawn:GetPos()
			end
			Spawn(spots)
		end,
		act = function() Give(Legs.Muster(Point(Named("red_muster")))) end,
		check = function()
			local lines, failures = Each({ Arrived, Runs("LegsStationary"), Resting,
				function(m) return InSpawnRoom(m), "left the spawn room" end })
			for _, failure in ipairs(Placement()) do failures[#failures + 1] = failure end
			for i, place in ipairs(B.places) do
				local start = B.starts[i]
				lines[i] = lines[i] .. string.format(" | from %.0f,%.0f placed %.0f,%.0f", start.x, start.y, place.x, place.y)
			end
			return Verdict(lines, failures)
		end,
	},
	{
		name = "mobilize",
		seconds = 25,
		setup = function() Spawn(Around(Named("red_muster"), SIZE, 72)) end,
		act = function() Give(Legs.Muster(Point(Ground(Staging())))) end,
		check = function()
			local staging = Staging()
			return Verdict(Each({ Arrived,
				function(m) return not InSpawnRoom(m), "still in the spawn room" end,
				function(m) return m:GetPos():Distance2D(staging) <= GATHERED, "not at the staging point" end }))
		end,
	},
	{
		name = "assault",
		seconds = 25,
		setup = function() Spawn(Around(Staging(), SIZE, 72)) end,
		act = function(run)
			local room = WS.Feature("aiwar"):RoomToAssault(Point(Named("bench_room")), Point(Staging()))
			B.room = room
			Give(Legs.Assault(room))
			WatchAssault(room, run)
		end,
		check = function()
			timer.Remove("dev_3house_bench_assault")
			local lines, failures = Each({ Arrived, Runs("LegsStationary"), Resting,
				function(m) return InBench(m), "not in the bench" end })
			local watch = B.watch
			if not B.order:Signalled() then failures[#failures + 1] = "the leader never signalled" end
			for i in pairs(watch.early) do failures[#failures + 1] = string.format("member %d: in before the signal", i) end
			for i in pairs(watch.seen) do failures[#failures + 1] = string.format("member %d: staged in the room's sight", i) end
			for _, failure in ipairs(Placement(true)) do failures[#failures + 1] = failure end
			for i, place in ipairs(B.places) do
				local stage = B.order:StagingOf(place)
				lines[i] = lines[i] .. string.format(" | staged %s placed %.0f,%.0f",
					stage and string.format("%.0f,%.0f", stage.x, stage.y) or "none", place.x, place.y)
			end
			return Verdict(lines, failures)
		end,
	},
	{
		name = "hold",
		seconds = 15,
		setup = function()
			Spawn(Around(Named("bench_room"), SIZE, 96))
			Give(Legs.Muster(Point(Named("bench_room"))))
		end,
		act = function() B.order:SetMode(Legs.MODE.ALERT) end,
		check = function()
			return Verdict(Each({ Runs("LegsPatrol"), function(m) return InBench(m), "left the bench" end }))
		end,
	},
	{
		name = "evacuate",
		seconds = 12,
		setup = function()
			Spawn(Around(Named("bench_room"), SIZE, 96))
			Give(Legs.Muster(Point(Named("bench_room"))))
		end,
		act = function()
			B.order:SetExits(WS.Feature("aiwar"):ExitsAt(B.order.point))
			WS.Feature("aiwar"):Mark("danger", WS.TEAM_RED, Point(Named("bench_danger")))
		end,
		check = function()
			local danger, room = Named("bench_danger"), Named("bench_room")
			local away = room:Distance2D(danger)
			local lines, failures = Each({ Runs("LegsEvacuate"),
				function(m) return not InBench(m), "still in the bench" end,
				function(m) return m:GetPos():Distance2D(danger) > away, "no further from the danger than the room" end })
			if not B.order.routed then failures[#failures + 1] = "the leader did not call the fall back" end
			return Verdict(lines, failures)
		end,
		cleanup = function() WS.Feature("aiwar"):Unmark(Named("bench_danger"), DANGER_UNMARK) end,
	},
	{
		name = "rout",
		seconds = 12,
		setup = function()
			Spawn(Around(Named("bench_room"), SIZE, 96))
			local order = Give(Legs.Muster(Point(Named("bench_room"))))
			order:SetExits(WS.Feature("aiwar"):ExitsAt(order.point))
		end,
		act = function()
			for i = SIZE - ROUT_KILLS + 1, SIZE do B.members[i]:TakeDamage(10000) end
		end,
		check = function()
			local lines, failures = Each({ Runs("LegsEvacuate"), function(m) return not InBench(m), "still in the bench" end })
			if not B.order.routed then failures[#failures + 1] = "the leader did not call the fall back" end
			return Verdict(lines, failures)
		end,
	},
	{
		name = "remuster",
		seconds = 12,
		setup = function() Spawn(Around(Named("bench_room") + OUTSIDE_WEST, SIZE, 72)) end,
		act = function() Give(Legs.Muster(Point(Ground(Staging())))) end,
		check = function()
			local rally = Staging()
			return Verdict(Each({ Arrived, Runs("LegsStationary"),
				function(m) return m:GetPos():Distance2D(rally) <= GATHERED, "not at the rally point" end }))
		end,
	},
}

local BY_NAME = {}
for _, stage in ipairs(B.STAGES) do BY_NAME[stage.name] = stage end

-- How long after its set-up a stage acts: the bodies settle and their trees start.
local SETTLE = 1

-- Runs a stage; its result lands in B.results[name], and then done(result) if given.
-- Each run started is numbered, and a run's timers act only while it is the newest: one started
-- over another ends the older, which would otherwise drive the same squad.
B.runs = B.runs or 0

function B.Run(name, done, run)
	local stage = BY_NAME[name]
	if not stage then error("no stage " .. tostring(name) .. "; stages: spawn muster mobilize assault hold evacuate rout remuster", 2) end
	if game.GetMap() ~= "dev_3house" then error("the bench runs on dev_3house, not " .. game.GetMap(), 2) end
	if not run then
		B.runs = B.runs + 1
		run = B.runs
	end
	B.results[name] = { running = true }
	-- TF2's forcefields stop only players, as the war has them while it runs
	WS.Feature("aiwar"):SetForcefieldsPassable(true)
	stage.setup()
	timer.Simple(SETTLE, function()
		if run ~= B.runs then return end
		if stage.act then stage.act(run) end
		timer.Simple(stage.seconds, function()
			if run ~= B.runs then return end
			local ok, result = pcall(stage.check)
			if stage.cleanup then stage.cleanup() end
			B.results[name] = ok and result or { passed = false, failures = { "check failed: " .. tostring(result) } }
			if done then done(B.results[name]) end
		end)
	end)
	return "running " .. name .. " (" .. (SETTLE + stage.seconds) .. " s)"
end

-- Runs every stage in turn, each from its own set-up, and clears the squad after; the last run's
-- results go first, so none is read as this one's.
function B.RunAll()
	B.results = {}
	B.runs = B.runs + 1
	local run = B.runs
	local total = 0
	for _, stage in ipairs(B.STAGES) do total = total + SETTLE + stage.seconds end
	local i = 0
	local function Next()
		i = i + 1
		local stage = B.STAGES[i]
		if not stage then Clear() return end
		B.Run(stage.name, Next, run)
	end
	Next()
	return "running all " .. #B.STAGES .. " stages (" .. total .. " s)"
end

-- Every stage's result so far, a line each, then the failures and members of those that failed.
function B.Report()
	local lines = {}
	for _, stage in ipairs(B.STAGES) do
		local result = B.results[stage.name]
		local state = not result and "not run" or result.running and "running" or result.passed and "passed" or "FAILED"
		lines[#lines + 1] = string.format("%-9s %s", stage.name, state)
	end
	for _, stage in ipairs(B.STAGES) do
		local result = B.results[stage.name]
		if result and result.passed == false then
			lines[#lines + 1] = "\n" .. stage.name .. ":"
			for _, failure in ipairs(result.failures or {}) do lines[#lines + 1] = "  " .. failure end
			for _, member in ipairs(result.members or {}) do lines[#lines + 1] = "  " .. member end
		end
	end
	return table.concat(lines, "\n")
end

-- One stage's result in full, passed or not: its failures, then each member's line.
function B.Show(name)
	local result = B.results[name]
	if not result then return name .. ": not run" end
	if result.running then return name .. ": running" end
	local lines = { name .. ": " .. (result.passed and "passed" or "FAILED") }
	for _, failure in ipairs(result.failures or {}) do lines[#lines + 1] = "  " .. failure end
	for _, member in ipairs(result.members or {}) do lines[#lines + 1] = "  " .. member end
	return table.concat(lines, "\n")
end

B.Clear = Clear
return "NSRoomBench loaded: " .. #B.STAGES .. " stages"
