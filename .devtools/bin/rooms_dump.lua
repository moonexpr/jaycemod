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

-- The spawns, the objectives and the visualizers as the controller reads
-- them (features/aiwar/sv_classes.lua).
local spawns, objectives, visualizers = Controller:SpawnAreas(), Controller:ObjectiveAreas(), Controller:Visualizers()

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
