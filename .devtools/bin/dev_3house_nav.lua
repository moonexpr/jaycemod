-- dev_3house's nav mesh, built on a live server on the map (.devtools/bin/dev_3house_map.py
-- builds the map), in two runs of this file:
--
--   1. With no mesh, it generates one: the spawn rooms' shutters opened and their visualizers
--      made passable, so the mesh walks out of the spawn rooms (both are solid to every trace the
--      generator makes), and a seed in each house and on the grass either side of the bench. The
--      engine saves the mesh and reloads the map when it is done.
--   2. With a mesh, it repairs it: the generator links a room's floor straight to the grass
--      outside across a doorway's threshold, areas that do not touch, and the war's rooms read
--      each such link as an opening the breadth of the room's side, so the bench reads as
--      outdoors. The doorway's own areas carry the walk through it, so those links are cut. The
--      generator also lays floor on the windows' sills, inside the walls, nearer a pane than
--      the floor either side of it, so the war's rooms find no window there; what no walk
--      from the seeds reaches is removed. The mesh is then saved. A repaired mesh is left as it
--      is.
--
-- To build it anew, remove maps/dev_3house.nav and change to the map again.
--   python3 .devtools/bin/instances.py dev_3house - < .devtools/bin/dev_3house_nav.lua
local SEEDS = { Vector(-1440, 0, 9), Vector(0, 0, 9), Vector(1440, 0, 9), Vector(-760, 400, 1), Vector(760, -400, 1) }
-- How long a shutter takes to rise out of the way.
local OPENING = 1.5
-- Areas further apart than this across the ground do not touch: the generator's areas share
-- their edges exactly.
local TOUCH = 1

if game.GetMap() ~= "dev_3house" then return "not on dev_3house: " .. game.GetMap() end

local function Generate()
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
	return "generating from " .. #SEEDS .. " seeds; run this again once the map has reloaded"
end

-- How far apart two areas lie across the ground: 0 where they touch or overlap.
local function Gap(a, b)
	local ea, eb = a:GetExtentInfo(), b:GetExtentInfo()
	return math.max(eb.lo.x - ea.hi.x, ea.lo.x - eb.hi.x, eb.lo.y - ea.hi.y, ea.lo.y - eb.hi.y, 0)
end

-- Every link, each way, between areas that do not touch.
local function Skipping()
	local links = {}
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		for _, other in ipairs(area:GetAdjacentAreas()) do
			if Gap(area, other) > TOUCH then links[#links + 1] = { area, other } end
		end
	end
	return links
end

-- The areas no walk from a seed reaches.
local function Stranded()
	local reached, stack = {}, {}
	for _, seed in ipairs(SEEDS) do
		local area = navmesh.GetNearestNavArea(seed)
		if IsValid(area) and not reached[area] then
			reached[area] = true
			stack[#stack + 1] = area
		end
	end
	while stack[1] do
		for _, other in ipairs(table.remove(stack):GetAdjacentAreas()) do
			if not reached[other] then
				reached[other] = true
				stack[#stack + 1] = other
			end
		end
	end
	local stranded = {}
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		if not reached[area] then stranded[#stranded + 1] = area end
	end
	return stranded
end

local function Repair()
	local links = Skipping()
	for _, link in ipairs(links) do link[1]:Disconnect(link[2]) end
	local stranded = Stranded()
	for _, area in ipairs(stranded) do area:Remove() end
	if #links == 0 and #stranded == 0 then return "repaired already: " .. navmesh.GetNavAreaCount() .. " areas" end
	-- an area removed leaves the mesh at the end of the tick: saved now, it would still be there
	timer.Simple(0, navmesh.Save)
	return string.format("cut %d links between areas that do not touch, removed %d areas no walk reaches; saving %d areas",
		#links, #stranded, navmesh.GetNavAreaCount() - #stranded)
end

if navmesh.GetNavAreaCount() == 0 then return Generate() end
return Repair()
