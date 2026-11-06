-- dev_3house's nav mesh, generated on a live server on the map (.devtools/bin/dev_3house_map.py
-- builds it): the spawn rooms' shutters opened and their visualizers made passable, so the mesh
-- walks out of the spawn rooms (both are solid to every trace the generator makes), and a seed
-- in each house and on the grass either side of the bench. The engine saves the mesh and
-- reloads the map when it is done.
--   python3 .devtools/bin/instances.py dev_3house - < .devtools/bin/dev_3house_nav.lua
local SEEDS = { Vector(-1440, 0, 9), Vector(0, 0, 9), Vector(1440, 0, 9), Vector(-760, 400, 1), Vector(760, -400, 1) }
-- How long a shutter takes to rise out of the way.
local OPENING = 1.5

if game.GetMap() ~= "dev_3house" then return "not on dev_3house: " .. game.GetMap() end
for _, door in ipairs(ents.FindByClass("func_door")) do door:Fire("Open") end
for _, field in ipairs(ents.FindByClass("func_respawnroomvisualizer")) do
	field:SetNotSolid(true)
	field:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
end
timer.Simple(OPENING, function()
	navmesh.ClearWalkableSeeds()
	for _, seed in ipairs(SEEDS) do navmesh.AddWalkableSeed(seed, Vector(0, 0, 1)) end
	navmesh.BeginGeneration()
end)
return "generating from " .. #SEEDS .. " seeds"
