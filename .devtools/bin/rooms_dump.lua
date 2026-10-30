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

print(util.TableToJSON({ map = game.GetMap(), areas = areas, windows = windows, spawns = spawns,
	objectives = objectives, visualizers = visualizers }))
