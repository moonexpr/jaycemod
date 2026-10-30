-- The running map's room graph and windows (the AI war controller's
-- RoomGraph, what wartactics.rooms.Partition is given) as JSON, with each
-- team's spawn areas and the objectives' areas, for rooms_view.py to
-- partition, class and draw off the server:
--     dt lua -f .devtools/bin/rooms_dump.lua > .devtools/artifacts/rooms/<map>.graph.json
-- Area ids are keys as strings; everything else is as the graph holds it.
-- A team's spawn areas: those its func_respawnroom holds (the npc
-- controller's SpawnRooms), and those its spawn points stand on
-- (the controller's TeamSpawns: TF2's team spawns, CS:S's terrorist and
-- counter-terrorist ones). The objectives: the areas under a capture area, a flag, a
-- hostage, a rescue zone or a bomb target, and the payload's track.
local Controller = WS.Feature("aiwar")
local graph, windows = Controller:RoomGraph({ CheckYield = function() end })
local areas = {}
for id, area in pairs(graph) do areas[tostring(id)] = area end

local TEAMS = { RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE }
local spawns = {}
local held = WS.Feature("npc"):SpawnRooms()
for name, team in pairs(TEAMS) do
	local set = {}
	for id, owner in pairs(held) do if owner == team then set[id] = true end end
	for _, point in ipairs(Controller:TeamSpawns(team)) do
		local area = navmesh.GetNearestNavArea(point:GetPos())
		if IsValid(area) then set[area:GetID()] = true end
	end
	local list = {}
	for id in pairs(set) do list[#list + 1] = id end
	table.sort(list)
	spawns[name] = list
end

local BRUSHES = { "trigger_capture_area", "func_hostage_rescue", "func_bomb_target" }
local POINTS = { "item_teamflag", "hostage_entity", "path_track" }
local objective = {}
for _, class in ipairs(BRUSHES) do
	for _, ent in ipairs(ents.FindByClass(class)) do
		local mins, maxs = ent:WorldSpaceAABB()
		for _, area in ipairs(navmesh.FindInBox(mins, maxs)) do objective[area:GetID()] = true end
	end
end
for _, class in ipairs(POINTS) do
	for _, ent in ipairs(ents.FindByClass(class)) do
		local area = navmesh.GetNearestNavArea(ent:GetPos())
		if IsValid(area) then objective[area:GetID()] = true end
	end
end
local objectives = {}
for id in pairs(objective) do objectives[#objectives + 1] = id end
table.sort(objectives)

-- The respawn room visualizers, which seal a spawn's doors: only behind
-- them is restricted ground.
local visualizers = {}
for _, ent in ipairs(ents.FindByClass("func_respawnroomvisualizer")) do
	local mins, maxs = ent:WorldSpaceAABB()
	visualizers[#visualizers + 1] = { lo = { x = mins.x, y = mins.y, z = mins.z }, hi = { x = maxs.x, y = maxs.y, z = maxs.z } }
end

-- The nav mesh's hiding spots, each with what it sees and what sees it,
-- among the areas within SIGHT_RANGE (traced against what is opaque, so
-- glass is seen through): sees, the areas whose middle, at a standing
-- player's chest, a player standing up from the spot sees; seen, the areas
-- from whose middle a player standing (at his eye) sees one crouched at
-- the spot (his head, CROUCH up), so a spot in plain sight of a player
-- standing can still hide one crouched. Every spot is taken, the mesh's
-- exposed ones too: crouching decides. The mesh carries no visibility of
-- its own (GetVisibleAreas is empty on converted meshes).
local SIGHT_RANGE, EYE, CHEST, CROUCH = 1024, Vector(0, 0, 64), Vector(0, 0, 48), Vector(0, 0, 40)
local HIDING = { cover = 1, sniper = 2, ideal = 4, exposed = 8 }
local hiding = {}
for id in pairs(graph) do
	local area = navmesh.GetNavAreaByID(id)
	local flags = {}
	for name, bit in pairs(HIDING) do
		for _, pos in ipairs(area:GetHidingSpots(bit) or {}) do
			local key = tostring(pos)
			flags[key] = flags[key] or { pos = pos }
			flags[key][name] = true
		end
	end
	for _, spot in pairs(flags) do
		local sees, seen = {}, {}
		for other, data in pairs(graph) do
			local c = Vector(data.center.x, data.center.y, data.center.z)
			if c:DistToSqr(spot.pos) <= SIGHT_RANGE * SIGHT_RANGE then
				if not util.TraceLine({ start = spot.pos + EYE, endpos = c + CHEST, mask = MASK_OPAQUE }).Hit then
					sees[#sees + 1] = other
				end
				if not util.TraceLine({ start = c + EYE, endpos = spot.pos + CROUCH, mask = MASK_OPAQUE }).Hit then
					seen[#seen + 1] = other
				end
			end
		end
		table.sort(sees)
		table.sort(seen)
		hiding[#hiding + 1] = { pos = { x = spot.pos.x, y = spot.pos.y, z = spot.pos.z }, area = id,
			cover = spot.cover == true, exposed = spot.exposed == true, sniper = spot.sniper == true or spot.ideal == true,
			sees = sees, seen = seen }
	end
end
table.sort(hiding, function(a, b) return a.area < b.area or (a.area == b.area and a.pos.x < b.pos.x) end)

print(util.TableToJSON({ map = game.GetMap(), areas = areas, windows = windows, spawns = spawns,
	objectives = objectives, visualizers = visualizers, hiding = hiding }))
