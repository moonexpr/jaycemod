-- Part of the AI war controller (sv.lua): the room classes from the
-- incursion, each team's spanning tree over the rooms, its breaching paths
-- and the ambush hints (docs/incursion-native-plan.md; wartactics.incursion,
-- classes and ambush). Found once a map on the slow lane, after the rooms,
-- from the room graph again (RoomGraph: the saved rooms keep no links), the
-- hiding spots' sight traced a slice at a time. They stand on graph.paths,
-- native: a server without the foundation binary finds none, and says so.
-- ns_classes_print says what was found.
local Controller = ...
local Incursion, Classes, Ambush = wartactics.incursion, wartactics.classes, wartactics.ambush
local Transaction = transaction

local CLASSES_TIME = 900
local TEAMS = { RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE }

-- The front's margin and how far is far, as shares of the walk between the
-- spawns; the forks junctions are carved at (each way a twentieth of the
-- map), a junction's reach and the floor it needs (a quarter of a room's
-- least); the breaches cover nine tenths of the map, ground within a room's
-- depth of a path covered; the ambushes: the last APPROACH of the walk up to
-- an entrance, a marking AMBUSH_NEAR to AMBUSH_FAR from it, up to
-- AMBUSH_KEEP an entrance; a hiding spot sees the areas within SIGHT_RANGE
-- whose middle, at a player's chest, a player standing up from it sees.
local FRONT_SHARE, FAR_SHARE, FORK_SHARE = 0.05, 0.2, 0.05
local JUNCTION_REACH, JUNCTION_FLOOR = 256, 10000
local COVER_SHARE, COVER_REACH = 0.9, 256
local APPROACH, AMBUSH_NEAR, AMBUSH_FAR, AMBUSH_KEEP = 384, 48, 384, 3
local SIGHT_RANGE, EYE, CHEST = 1024, Vector(0, 0, 64), Vector(0, 0, 48)
local IN_COVER, EXPOSED = 1, 8
local TRACES_A_SLICE = 64

-- Each team's spawn areas, by RED and BLU: those its func_respawnroom holds
-- (the npc controller's SpawnRooms) and those its spawns stand on
-- (TeamSpawns: TF2's team spawns, CS:S's sides).
function Controller:SpawnAreas()
	local held, spawns = WS.Feature("npc"):SpawnRooms(), {}
	for name, team in pairs(TEAMS) do
		local set = {}
		for id, owner in pairs(held) do if owner == team then set[id] = true end end
		for _, point in ipairs(self:TeamSpawns(team)) do
			local area = navmesh.GetNearestNavArea(point:GetPos())
			if IsValid(area) then set[area:GetID()] = true end
		end
		local list = {}
		for id in pairs(set) do list[#list + 1] = id end
		table.sort(list)
		spawns[name] = list
	end
	return spawns
end

-- The objectives' areas: under a capture area, a flag, a hostage, a rescue
-- zone or a bomb target, and the payload's track.
local OBJECTIVE_BRUSHES = { "trigger_capture_area", "func_hostage_rescue", "func_bomb_target" }
local OBJECTIVE_POINTS = { "item_teamflag", "hostage_entity", "path_track" }

function Controller:ObjectiveAreas()
	local set = {}
	for _, class in ipairs(OBJECTIVE_BRUSHES) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			local mins, maxs = ent:WorldSpaceAABB()
			for _, area in ipairs(navmesh.FindInBox(mins, maxs)) do set[area:GetID()] = true end
		end
	end
	for _, class in ipairs(OBJECTIVE_POINTS) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			local area = navmesh.GetNearestNavArea(ent:GetPos())
			if IsValid(area) then set[area:GetID()] = true end
		end
	end
	local list = {}
	for id in pairs(set) do list[#list + 1] = id end
	table.sort(list)
	return list
end

-- The respawn room visualizers' boxes, which seal a spawn's doors.
function Controller:Visualizers()
	local boxes = {}
	for _, ent in ipairs(ents.FindByClass("func_respawnroomvisualizer")) do
		local mins, maxs = ent:WorldSpaceAABB()
		boxes[#boxes + 1] = { lo = { x = mins.x, y = mins.y, z = mins.z }, hi = { x = maxs.x, y = maxs.y, z = maxs.z } }
	end
	return boxes
end

-- The nav mesh's hiding spots on the room graph's areas, in cover or
-- exposed, each with the areas it sees (traced against what is opaque).
local function HidingSpots(graph, work)
	local spots, traces = {}, 0
	local ids = {}
	for id in pairs(graph) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local area, seen = navmesh.GetNavAreaByID(id), {}
		for _, kind in ipairs({ IN_COVER, EXPOSED }) do
			for _, pos in ipairs(area:GetHidingSpots(kind) or {}) do
				local key = tostring(pos)
				if not seen[key] then
					seen[key] = true
					local sees, eye = {}, pos + EYE
					for other, data in pairs(graph) do
						local c = Vector(data.center.x, data.center.y, data.center.z)
						if c:DistToSqr(pos) <= SIGHT_RANGE * SIGHT_RANGE then
							if not util.TraceLine({ start = eye, endpos = c + CHEST, mask = MASK_OPAQUE }).Hit then sees[other] = true end
							traces = traces + 1
							if traces % TRACES_A_SLICE == 0 then work:CheckYield() end
						end
					end
					spots[#spots + 1] = { pos = { x = pos.x, y = pos.y, z = pos.z }, area = id, sees = sees }
				end
			end
		end
	end
	return spots
end

local function Teams(spawns)
	local teams = {}
	for team in pairs(spawns) do teams[#teams + 1] = team end
	table.sort(teams)
	return teams
end

-- Every stage, on the room graph, its windows and the rooms found on it.
local function Find(graph, windows, partition, spawns, objectives, seals, spots, yield)
	local function region(area) return Classes.Region(partition, area) end
	local g = Incursion.Graph(graph, windows)
	local fields = Incursion.Fields(g, spawns)
	local routes = Incursion.Routes(g, spawns, fields)
	yield()
	local edges = Classes.SpaceGraph(partition)
	local homes = {}
	for team, areas in pairs(spawns) do
		local set, list = {}, {}
		for _, a in ipairs(areas) do
			local space = region(a)
			if space and not set[space] then set[space], list[#list + 1] = true, space end
		end
		homes[team] = list
	end
	local restricted = Classes.Restricted(edges, homes, seals)
	local highways = Classes.Highways(routes, region, objectives, restricted, spawns)
	local places, owner = Classes.Places(edges, homes)
	local separation = math.huge
	for _, team in ipairs(Teams(spawns)) do
		for _, enemy in ipairs(Teams(spawns)) do
			if enemy ~= team then
				for _, a in ipairs(spawns[enemy]) do
					local d = g.node[a] and fields[team]:Distance(g.node[a])
					if d and d < separation then separation = d end
				end
			end
		end
	end
	local classed = Classes.Classify(partition, g, fields, restricted, highways, owner, FRONT_SHARE * separation,
		FAR_SHARE * separation)
	yield()
	local trees, spaceTrees, breaches, forks, seenFork = {}, {}, {}, {}, {}
	for _, team in ipairs(Teams(spawns)) do
		trees[team] = Incursion.Tree(g, fields[team])
		spaceTrees[team] = Classes.SpaceTree(trees[team], region)
		breaches[team] = Incursion.Breaches(g, fields[team], COVER_SHARE, COVER_REACH)
		for _, a in ipairs(Incursion.Forks(g, fields[team], FORK_SHARE)) do
			if not seenFork[a] then seenFork[a], forks[#forks + 1] = true, a end
		end
	end
	table.sort(forks)
	local junctions = Classes.Junctions(forks, graph, g, region, JUNCTION_REACH, JUNCTION_FLOOR)
	yield()
	local paths = {}
	for _, route in ipairs(routes) do
		if not route.alternative then paths[#paths + 1] = route end
	end
	for team, mine in pairs(breaches) do
		for _, breach in ipairs(mine) do paths[#paths + 1] = { team = team, areas = breach.areas } end
	end
	local entrances = Ambush.Entrances(paths, g.crossings, region, APPROACH)
	local kept, count = {}, {}
	for _, mark in ipairs(Ambush.Ambushes(entrances, spots, fields, g, region, AMBUSH_NEAR, AMBUSH_FAR)) do
		local key = mark.team .. ":" .. mark.entrance.outside .. ":" .. mark.entrance.inside
		if (count[key] or 0) < AMBUSH_KEEP then
			kept[#kept + 1], count[key] = mark, (count[key] or 0) + 1
		end
	end
	return { classed = classed, highways = highways, restricted = restricted, places = places, owner = owner,
		trees = spaceTrees, breaches = breaches, junctions = junctions, entrances = entrances, ambushes = kept,
		routes = #routes, spots = #spots }
end

-- The classes, trees, breaches and ambushes, or nil while the rooms or they
-- are being found (the first ask starts that, on the slow lane).
function Controller:Classes()
	if self.classes then return self.classes end
	local partition = self:Rooms()
	if not partition or self.classesFinding then return nil end
	self.classesFinding = Transaction.Spawn(WS.SlowTransactions, function(work)
		local graph, windows = self:RoomGraph(work)
		local spots = HidingSpots(graph, work)
		local spawns, objectives, seals = self:SpawnAreas(), self:ObjectiveAreas(), self:Visualizers()
		return Find(graph, windows, partition, spawns, objectives, seals, spots, function() work:CheckYield() end)
	end):Within(WS.Deadline(CLASSES_TIME))
	self.classesFinding:OnSettle(function(settled)
		self.classesFinding = nil
		if settled:State() ~= Transaction.COMMITTED then
			self.classesFailed = tostring(settled:Error() or Transaction.Message(settled:Refusal()))
			ErrorNoHalt("AI war: the room classes were not found: " .. self.classesFailed .. "\n")
			return
		end
		self.classesFailed = nil
		self.classes = settled:Value()
	end)
	return nil
end

-- A room's or corridor's name as the tooling's pictures label it.
local function Name(space)
	if space.kind == "corridor" then return "C" .. space.id end
	return (space.kind == "stairwell" and "S" or space.outdoor and "O" or "R") .. space.id
end

local function Names(set)
	local names = {}
	for space in pairs(set) do names[#names + 1] = Name(space) end
	table.sort(names)
	return table.concat(names, ", ")
end

-- ns_classes_print's lines: the classes, the highways, the junctions, and
-- each team's tree, breaches and ambush markings.
function Controller:ClassReport()
	local found = self:Classes()
	if not found then
		if self.classesFailed then return { "ns_classes_print: not found: " .. self.classesFailed } end
		return { "ns_classes_print: the rooms and their classes are being found; ask again in a moment" }
	end
	local counts = {}
	for _, placed in pairs(found.classed) do
		local name = placed.cls .. (placed.team and " " .. placed.team or "")
		counts[name] = (counts[name] or 0) + 1
	end
	local names = {}
	for name, n in pairs(counts) do names[#names + 1] = n .. " " .. name end
	table.sort(names)
	local junctions = {}
	for _, j in ipairs(found.junctions) do junctions[#junctions + 1] = #j.areas .. " areas of " .. Name(j.space) end
	local lines = {
		string.format("ns_classes_print: %s; from %d routes and %d hiding spots", table.concat(names, ", "), found.routes,
			found.spots),
		"highways: " .. Names(found.highways),
		string.format("junctions: %d: %s", #found.junctions, table.concat(junctions, ", ")),
	}
	for _, team in ipairs(Teams(found.trees)) do
		local tree = found.trees[team]
		local roots = {}
		for _, root in ipairs(tree.roots) do roots[#roots + 1] = Name(root) end
		local spaces = 0
		for _ in pairs(tree.entry) do spaces = spaces + 1 end
		local marks, at = 0, {}
		for _, mark in ipairs(found.ambushes) do
			if mark.team == team then marks, at[mark.entrance] = marks + 1, true end
		end
		local entrances = 0
		for _ in pairs(at) do entrances = entrances + 1 end
		lines[#lines + 1] = string.format("%s: a tree of %d spaces from %s; %d breaching paths; lying in wait, %d markings at %d entrances",
			team, spaces, table.concat(roots, ", "), #found.breaches[team], marks, entrances)
	end
	return lines
end

-- The overlay's part of them (the game_aiwar_rooms event, features/nbdebug/
-- sh.lua), or nil until found: by room id its class, team (the game's
-- number, 0 for none) and gradient (a percent); each team's tree as
-- branches between the entries of its spaces; the junctions' blocks; the
-- ambush markings, a spot and the entrance it covers. Capped at what the
-- event carries.
local TEAM_ID = { RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE }
local BRANCHES_MAX, JUNCTIONS_MAX, AMBUSHES_MAX = 1023, 63, 255

local function Centre(id)
	local area = navmesh.GetNavAreaByID(id)
	return IsValid(area) and area:GetCenter() or nil
end

local function V(p) return Vector(p.x, p.y, p.z) end

function Controller:ClassesDebug()
	local found = self:Classes()
	if not found then return nil end
	local rooms = {}
	for room, placed in pairs(found.classed) do
		rooms[room.id] = { class = placed.cls, team = TEAM_ID[placed.team] or 0,
			gradient = math.Round(math.Clamp(placed.gradient, 0, 1) * 100) }
	end
	local branches = {}
	for _, team in ipairs(Teams(found.trees)) do
		local tree = found.trees[team]
		for space, up in pairs(tree.parent) do
			local from, to = Centre(tree.entry[up]), Centre(tree.entry[space])
			if from and to and #branches < BRANCHES_MAX then
				branches[#branches + 1] = { team = TEAM_ID[team], from = from, to = to }
			end
		end
	end
	local junctions = {}
	for i = 1, math.min(#found.junctions, JUNCTIONS_MAX) do
		local lo, hi
		for _, id in ipairs(found.junctions[i].areas) do
			local area = navmesh.GetNavAreaByID(id)
			if IsValid(area) then
				local e = area:GetExtentInfo()
				lo = lo and Vector(math.min(lo.x, e.lo.x), math.min(lo.y, e.lo.y), math.min(lo.z, e.lo.z)) or e.lo
				hi = hi and Vector(math.max(hi.x, e.hi.x), math.max(hi.y, e.hi.y), math.max(hi.z, e.hi.z)) or e.hi
			end
		end
		if lo then junctions[#junctions + 1] = { lo = lo, hi = hi } end
	end
	local ambushes = {}
	for i = 1, math.min(#found.ambushes, AMBUSHES_MAX) do
		local mark = found.ambushes[i]
		ambushes[i] = { team = TEAM_ID[mark.team], spot = V(mark.spot.pos), via = V(mark.entrance.via) }
	end
	return { rooms = rooms, branches = branches, junctions = junctions, ambushes = ambushes }
end
