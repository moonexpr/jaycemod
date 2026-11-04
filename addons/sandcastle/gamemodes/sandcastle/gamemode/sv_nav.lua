-- The map's navigation mesh, which every NextBot walks (the AI war's
-- soldiers, the bosses). TF2 ships a mesh for few of its maps (its bots
-- generate one), and GMod cannot load TF2's own (.devtools/bin/nav_convert.py
-- converts those). mp_nav_generate, for admins and the server console,
-- builds one: GMod's generator walks out from seeds, and TF2 maps spawn
-- players at info_player_teamspawn, which it does not seed from, so every
-- spawn point and control point is a seed, as is every health and ammo pack:
-- a map puts them where players are meant to get, and some only by ways
-- the generator cannot walk up (arena_watchtower's west pipe, reached by
-- logs too narrow for its 25-unit steps). It walks only what stands in
-- place. Existing hiding spots and BSP ladder endpoints are seeds too;
-- native nav ladders are connected to the generated areas and saved after
-- generation. A map's spawn doors, setup gates and bridges (cp_steel's slide
-- out to its last point as the others fall) stand shut or drawn back: every
-- door is unlocked, and opened, or closed when it is a floor (flat and
-- wide: a bridge, laid out by closing it), spawn barriers are made
-- passable, and it
-- begins once no door moves (or after DOOR_WAIT). The generator walks
-- through every door (Source's IsEntityWalkable), a laid bridge too, so each
-- floor gets a stand-in it walks on: an always-solid func_brush of the
-- floor's own brush where it lies, gone with the map reset. It runs in Sandbox mode
-- (entered first; refused while sv_gameplay_disable_sandbox forbids it), so
-- no round closes a door meanwhile, with every spawn limit (sbox_max<kind>,
-- one per cleanup kind) at 0 so nothing new stands in its way. When it is
-- done GMod has saved maps/<map>.nav, the limits are put back, the map is
-- reset (its doors and gates put back), and the admin who started it is
-- told. Every client's progress box follows each stage
-- (WS.NavProgress, ws/sh_nav_progress.lua). Meanwhile spawning is locked
-- (WS.LockSpawns, ws/sv_spawn_manager.lua): players still join, but nobody
-- picks a team or spawns until it is done.
--
-- An idle server builds its own: once it is idle (WSServerIdle,
-- ws/sv_idle.lua) on a map with no mesh, it runs as the console's would, and
-- goes back to Gameplay mode when it left it to generate, so the rounds and
-- the next-map vote carry on.
local Gamemode = system.gamemode
local Doors = nextsoldier.world.doors
local Progress = WS.require("includes.nav_progress")
local World = nextsoldier.world
local NavGaps = nextsoldier.world.nav_gaps
local NavStairs = nextsoldier.world.nav_stairs
local NavClearance = WS.require("includes.nav_clearance")
local PairMap = world.pairmap

local SEEDS = { "info_player_teamspawn", "info_player_start", "team_control_point", "item_healthkit_small",
	"item_healthkit_medium", "item_healthkit_full", "item_ammopack_small", "item_ammopack_medium", "item_ammopack_full" }
local LADDER_CLASSES = { func_ladder = true, func_useableladder = true, info_ladder = true }
local LADDER_WIDTH = 32
local LADDER_TOP_ADJUST = 128
local LADDER_DISMOUNT_REACH = 128
local LADDER_AREA_REACH = 128
-- How far off a ladder's brush its wall is looked for (GenerationStepSize).
local LADDER_WALL_STEP = 25
-- How far over its wall a ladder's upper floor is looked for.
local LADDER_OVER = 32
local LADDERS_REBUILD = "ws_nav_ladders"
-- Seconds a removed ladder is waited for: it goes after the frame's timers, so
-- a timer of 0 would save it beside its replacement.
local LADDERS_REMOVED_WAIT = 0.5
local DOORS = { "func_door", "func_door_rotating", "prop_door_rotating" }
local BARRIERS = { "func_respawnroomvisualizer" }
local DOOR_WAIT = 60
local POLL = "ws_nav_generate"

-- func_door's m_toggle_state while opening or closing; prop_door_rotating's
-- m_eDoorState
local TOGGLE_MOVING = { [2] = true, [3] = true }
local PROP_DOOR_MOVING = { [1] = true, [3] = true }

local underWay = false


function WS.NavMeshUsable()
	return navmesh.IsLoaded() and navmesh.GetNavAreaCount() > 0
end

-- The masks walkers move under on this map, and the traces that stand in
-- for their walking take (nextsoldier.world: on a players' map, the
-- player's clips), read off the map's entities once.
local CLIP_MASKS = {
	[World.CLIP_PLAYER] = { solid = MASK_PLAYERSOLID, brushes = MASK_PLAYERSOLID_BRUSHONLY },
	[World.CLIP_NPC] = { solid = MASK_NPCSOLID, brushes = MASK_NPCSOLID_BRUSHONLY },
}
local clipMasks

function WS.ClipMasks()
	if not clipMasks then
		local classes = {}
		for i, ent in ipairs(ents.GetAll()) do classes[i] = ent:GetClass() end
		clipMasks = CLIP_MASKS[World.ClipFor(classes)]
	end
	return clipMasks
end

function WS.NavHullClearance(entity, mask)
	return NavClearance.New(entity, mask, util.TraceHull, Vector)
end

-- The mesh's seams (nextsoldier.world.nav_gaps), linked both ways where a walker
-- crosses: a soldier's hull above step height sweeps across clear under the
-- clip masks, and finds floor (a clip brush counts) under the seam. Swept
-- GAP_BATCH a tick, to keep the tick short; once the map's mesh has loaded
-- and after mp_nav_generate, since the links live only in memory.
local GAP_BATCH = 64
local GAP_TIMER = "ws_nav_gaps"
-- the standard body's width (a TF2 player's, gameplay.movement): a seam a
-- narrower box crosses can be too narrow for the bots' shoulders
local BODY = gameplay.movement.TF2
local CROSS_MINS, CROSS_MAXS = Vector(BODY.hullMin.x, BODY.hullMin.y, 0), Vector(BODY.hullMax.x, BODY.hullMax.y, 72 - NavGaps.STEP_HEIGHT)
local BODY_MAXS = Vector(BODY.hullMax.x, BODY.hullMax.y, 72)
local STEP = Vector(0, 0, NavGaps.STEP_HEIGHT)
-- the floor under a seam is looked for under the feet, not the shoulders
local FLOOR_MINS, FLOOR_MAXS = Vector(-12, -12, 0), Vector(12, 12, 1)

local function V(p) return Vector(p.x, p.y, p.z) end
local function Point(v) return { x = v.x, y = v.y, z = v.z } end

local function Crosses(from, to, mask)
	local across = util.TraceHull({ start = from + STEP, endpos = to + STEP, mins = CROSS_MINS, maxs = CROSS_MAXS, mask = mask })
	if across.Hit or across.StartSolid then return false end
	local middle = (from + to) / 2
	local below = util.TraceHull({ start = middle + STEP, endpos = middle - STEP, mins = FLOOR_MINS, maxs = FLOOR_MAXS, mask = mask })
	return below.Hit and not below.StartSolid
end

-- Whether a walker crosses the link from area a into area b (a lane over
-- it): its lines across the opening (nextsoldier.world.nav_gaps' CrossingLines,
-- as a path may cross anywhere along it) clear at a step's, a waist's and a
-- chest's height under the clip masks' brushes (the map alone, not who
-- stands there), so a players' map's clip along a rail (a bullet passes it,
-- a player does not) refuses the drop past it the nav mesh links, and a
-- wall's end refuses the link the mesh draws past it beside a doorway.
-- Kept for the mesh (cleared as the gaps are bridged anew: after it loads
-- and is generated).
local CROSS_HEIGHTS = { NavGaps.STEP_HEIGHT + 2, 36, 60 }
-- The map as it stands for good: the world and the brushes that never move
-- (a window, a wall). Not a door, which opens, nor a spawn room's
-- visualizer, solid to the other team alone: the answer is kept.
local STATIC_BRUSHES = { func_brush = true, func_wall = true }
local function StaticMap(ent)
	return ent:IsWorld() or STATIC_BRUSHES[ent:GetClass()] == true
end
-- How far down a drop's floor is looked for.
local FLOOR_DEPTH = 1000
-- each link's answer, by its two areas' ids: asked for every link a path
-- weighs, so looked up without building a key
local crossable = PairMap.New()

-- Whether the standard body fits, or a supplied agent hull fits, somewhere
-- along the opening (nextsoldier.world.nav_gaps' FitLines, middle first).
local function BodyFits(lo, hi, side, otherLo, otherHi, z, mask, hullMins, hullMaxs)
	local lines = NavGaps.FitLines(lo, hi, side, otherLo, otherHi, z)
	return NavClearance.FitsLines(lines, hullMins or CROSS_MINS, hullMaxs or BODY_MAXS, mask, util.TraceHull, Vector)
end

function WS.NavLinkCrossable(a, b, hullMins, hullMaxs)
	local aId, bId = a:GetID(), b:GetID()
	local agentHull = hullMins ~= nil and hullMaxs ~= nil
	local known
	if not agentHull then known = crossable:Get(aId, bId) end
	if known ~= nil then return known end
	-- across the side the link leaves by (filed on none: the side toward b),
	-- where b borders it
	local center = a:GetCenter()
	local side = NavGaps.SideToward(Point(center), Point(b:GetCenter()))
	for dir = 0, 3 do
		if table.HasValue(a:GetAdjacentAreasAtSide(dir), b) then side = dir break end
	end
	local extent, other = a:GetExtentInfo(), b:GetExtentInfo()
	local lo, hi, otherLo, otherHi = Point(extent.lo), Point(extent.hi), Point(other.lo), Point(other.hi)
	-- heights where the areas meet, not at their centres: a ramp's centre
	-- stands well above or below its edge, which meets the next area flush
	local middleStart, middleFinish = NavGaps.CrossingLine(lo, hi, side, otherLo, otherHi, 0)
	local seamFrom, seamTo = a:GetZ(V(middleFinish)), b:GetZ(V(middleFinish))
	-- the lines run above the floor all along them
	local z = math.max(a:GetZ(V(middleStart)), seamFrom, seamTo)
	local mask = WS.ClipMasks().brushes
	local clear = true
	for _, line in ipairs(NavGaps.CrossingLines(lo, hi, side, otherLo, otherHi, z)) do
		for _, h in ipairs(CROSS_HEIGHTS) do
			local up = Vector(0, 0, h)
			if util.TraceLine({ start = V(line.start) + up, endpos = V(line.finish) + up, mask = mask, filter = StaticMap }).Hit then
				clear = false
				break
			end
		end
		if not clear then break end
	end
	if clear then
		local _, finish = NavGaps.CrossingLine(lo, hi, side, otherLo, otherHi, z)
		local floor = util.TraceLine({ start = V(finish) + STEP, endpos = V(finish) - Vector(0, 0, FLOOR_DEPTH), mask = mask, filter = StaticMap })
		clear = NavGaps.FallsAway(seamFrom, seamTo, floor.Hit and floor.HitPos.z or nil)
	end
	clear = clear and BodyFits(lo, hi, side, otherLo, otherHi, z, mask, hullMins, hullMaxs)
	if not agentHull then crossable:Set(aId, bId, clear) end
	return clear
end

function WS.BridgeNavGaps()
	timer.Remove(GAP_TIMER)
	crossable:Clear()
	NavClearance.Clear()
	if not WS.NavMeshUsable() then return end
	local byId, areas = {}, {}
	for i, area in ipairs(navmesh.GetAllNavAreas()) do
		local extent = area:GetExtentInfo()
		byId[area:GetID()] = area
		areas[i] = { id = area:GetID(), lo = Point(extent.lo), hi = Point(extent.hi) }
	end
	local candidates = NavGaps.Candidates(areas,
		function(id, x, y) return byId[id]:GetZ(Vector(x, y, 0)) end,
		function(from, to) return byId[from]:IsConnected(byId[to]) end)
	local mask, next, linked = WS.ClipMasks().brushes, 1, 0
	timer.Create(GAP_TIMER, 0, 0, function()
		for i = next, math.min(next + GAP_BATCH - 1, #candidates) do
			local c = candidates[i]
			local a, b = byId[c.a], byId[c.b]
			if IsValid(a) and IsValid(b) and Crosses(V(c.from), V(c.to), mask) then
				if not a:IsConnected(b) then a:ConnectTo(b) end
				if not b:IsConnected(a) then b:ConnectTo(a) end
				linked = linked + 1
			end
		end
		next = next + GAP_BATCH
		if next > #candidates then
			timer.Remove(GAP_TIMER)
			print(string.format("Navigation mesh: linked %d of %d seams between areas", linked, #candidates))
			-- routes planned before may lack the ways just linked
			if linked > 0 then hook.Run("WSNavLinked") end
		end
	end)
end

-- How far around a clip's bounds a flight's floors are looked for: the mesh's areas
-- stop short of a clip's end, and they stand up to a step or so off its height.
local STAIR_REACH = Vector(NavStairs.END_REACH, NavStairs.END_REACH, 32)
local CORNER_NW, CORNER_NE, CORNER_SE, CORNER_SW = 0, 1, 2, 3

local function StairArea(area)
	local extent, links = area:GetExtentInfo(), {}
	for i, other in ipairs(area:GetAdjacentAreas()) do links[i] = other:GetID() end
	return {
		id = area:GetID(), lo = Point(extent.lo), hi = Point(extent.hi), links = links,
		z = {
			nw = area:GetCorner(CORNER_NW).z, ne = area:GetCorner(CORNER_NE).z,
			se = area:GetCorner(CORNER_SE).z, sw = area:GetCorner(CORNER_SW).z,
		},
	}
end

-- The ramp a plan lays (nextsoldier.world.nav_stairs), in place of the fragments.
local function LayRamp(plan)
	local nw = Vector(plan.lo.x, plan.lo.y, plan.z.nw)
	local se = Vector(plan.hi.x, plan.hi.y, plan.z.se)
	local ramp = navmesh.CreateNavArea(nw, se)
	if not IsValid(ramp) then return false end
	ramp:SetCorner(CORNER_NW, nw)
	ramp:SetCorner(CORNER_NE, Vector(plan.hi.x, plan.lo.y, plan.z.ne))
	ramp:SetCorner(CORNER_SE, se)
	ramp:SetCorner(CORNER_SW, Vector(plan.lo.x, plan.hi.y, plan.z.sw))
	ramp:AddAttributes(NAV_MESH_STAIRS)
	for _, id in ipairs(plan.remove) do navmesh.GetNavAreaByID(id):Remove() end
	for _, id in ipairs(plan.connect) do
		local other = navmesh.GetNavAreaByID(id)
		ramp:ConnectTo(other)
		other:ConnectTo(ramp)
	end
	return true
end

-- The stairs the generator broke, by the map's slanted player clips, each made
-- one ramp; the mesh saved when any was, so a map is repaired once. An area
-- removed leaves the mesh a tick later, so the save and then done wait for it.
function WS.RepairNavStairs(done)
	local brushes = WS.MapFile({ "BRUSHES", "BRUSHSIDES", "PLANES" }).BRUSHES
	local slopes = NavStairs.Slopes(brushes)
	local repaired = 0
	for _, slope in ipairs(slopes) do
		local mins = Vector(slope.lo.x, slope.lo.y, slope.lo.z) - STAIR_REACH
		local maxs = Vector(slope.hi.x, slope.hi.y, slope.hi.z) + STAIR_REACH
		local areas = {}
		for i, area in ipairs(navmesh.FindInBox(mins, maxs)) do areas[i] = StairArea(area) end
		local plan = NavStairs.Plan(slope, areas)
		if plan and LayRamp(plan) then repaired = repaired + 1 end
	end
	print(string.format("Navigation mesh: %d of %d clipped stairs repaired", repaired, #slopes))
	if repaired == 0 then return done() end
	timer.Simple(0, function()
		navmesh.Save()
		done()
	end)
end

-- GMod loads the mesh after the map's entities: the sweep waits for it, a
-- second at a time, up to NAV_LOAD_WAIT (a map without one never has it).
local NAV_LOAD_WAIT = 60

hook.Add("InitPostEntity", "ws_nav_gaps", function()
	timer.Create(GAP_TIMER, 1, NAV_LOAD_WAIT, function()
		if WS.NavMeshUsable() then
			timer.Remove(GAP_TIMER)
			WS.RepairNavStairs(WS.BridgeNavGaps)
		end
	end)
end)

local function Tell(ply, text)
	if IsValid(ply) then ply:ChatPrint(text) else print(text) end
end

local function Each(classes, fn)
	for _, class in ipairs(classes) do
		for _, ent in ipairs(ents.FindByClass(class)) do fn(ent) end
	end
end

local function IsFloor(door)
	local mins, maxs = door:OBBMins(), door:OBBMaxs()
	return Doors.IsFloor({ x = maxs.x - mins.x, y = maxs.y - mins.y, z = maxs.z - mins.z })
end

local function ParseVector(value)
	local x, y, z = string.match(value or "", "^%s*(%S+)%s+(%S+)%s+(%S+)%s*$")
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not x or not y or not z or x ~= x or y ~= y or z ~= z
		or math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge then
		return nil
	end
	return Vector(x, y, z)
end

local function Cardinal(vector)
	if not vector then return nil end
	if math.abs(vector.x) >= math.abs(vector.y) and math.abs(vector.x) > 0 then
		return Vector(vector.x > 0 and 1 or -1, 0, 0)
	elseif math.abs(vector.y) > 0 then
		return Vector(0, vector.y > 0 and 1 or -1, 0)
	end
	return nil
end

local function ParseBounds(values)
	local function Coordinate(key)
		local value = tonumber(values[key])
		if not value or value ~= value or math.abs(value) == math.huge then return nil end
		return value
	end
	local minX, minY, minZ = Coordinate("mins.x"), Coordinate("mins.y"), Coordinate("mins.z")
	local maxX, maxY, maxZ = Coordinate("maxs.x"), Coordinate("maxs.y"), Coordinate("maxs.z")
	if not (minX and minY and minZ and maxX and maxY and maxZ) then return nil end
	local mins, maxs = Vector(minX, minY, minZ), Vector(maxX, maxY, maxZ)
	if mins.x > maxs.x or mins.y > maxs.y or mins.z >= maxs.z then return nil end
	return mins, maxs
end

local function BoundsDistance(pos, mins, maxs)
	local x = math.max(mins.x - pos.x, 0, pos.x - maxs.x)
	local y = math.max(mins.y - pos.y, 0, pos.y - maxs.y)
	local z = math.max(mins.z - pos.z, 0, pos.z - maxs.z)
	return math.sqrt(x * x + y * y + z * z)
end

local function BoundsDirection(mins, maxs, dismounts)
	local xSize, ySize = maxs.x - mins.x, maxs.y - mins.y
	local axis = xSize <= ySize and "x" or "y"
	local center = (mins[axis] + maxs[axis]) / 2
	local nearest, nearestDistance
	for _, pos in ipairs(dismounts) do
		local distance = BoundsDistance(pos, mins, maxs)
		if not nearestDistance or distance < nearestDistance then
			nearest, nearestDistance = pos, distance
		end
	end
	if not nearest or nearestDistance > LADDER_DISMOUNT_REACH then return nil end
	local offset = nearest[axis] - center
	if offset == 0 then return nil end
	if axis == "x" then return Vector(offset > 0 and 1 or -1, 0, 0) end
	return Vector(0, offset > 0 and 1 or -1, 0)
end

local function LadderDirection(normal)
	return Cardinal(normal)
end

-- A ladder's facing with no dismount beside it (any plain CS map), as
-- CNavMesh::BuildLadders finds it: a line up each side of the brush, one step
-- off and clear of the floor and ceiling. The side that hits is its wall, and
-- it faces the other; both or neither says nothing.
local function WallFacing(mins, maxs)
	local axis = maxs.x - mins.x <= maxs.y - mins.y and "x" or "y"
	local center = Vector((mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2, 0)
	local function Walled(sign)
		local from, to = Vector(center.x, center.y, mins.z + LADDER_WALL_STEP / 2), Vector(center.x, center.y, maxs.z - LADDER_WALL_STEP / 2)
		from[axis], to[axis] = center[axis] + sign * LADDER_WALL_STEP, center[axis] + sign * LADDER_WALL_STEP
		local trace = util.TraceLine({ start = from, endpos = to, mask = MASK_NPCSOLID_BRUSHONLY })
		return trace.Hit or trace.StartSolid
	end
	local plus, minus = Walled(1), Walled(-1)
	if plus == minus then return nil end
	local away = plus and -1 or 1
	if axis == "x" then return Vector(away, 0, 0) end
	return Vector(0, away, 0)
end

local function Ladders()
	local entities = WS.MapFile({ "ENTITIES" }).ENTITIES
	local ladders, dismounts, records = {}, {}, {}
	for _, pairs in ipairs(entities) do
		local values = {}
		for _, pair in ipairs(pairs) do values[pair.key] = pair.value end
		if values.classname == "info_ladder_dismount" then
			local pos = ParseVector(values.origin)
			if pos then dismounts[#dismounts + 1] = pos end
		elseif LADDER_CLASSES[values.classname] then
			records[#records + 1] = values
		end
	end
	for _, values in ipairs(records) do
		if values.classname == "info_ladder" then
			local mins, maxs = ParseBounds(values)
			if mins and maxs then
				ladders[#ladders + 1] = {
					top = Vector((mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2, maxs.z),
					bottom = Vector((mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2, mins.z),
					width = math.max(maxs.x - mins.x, maxs.y - mins.y),
					direction = BoundsDirection(mins, maxs, dismounts) or WallFacing(mins, maxs),
					mins = mins,
					maxs = maxs,
					id = values.hammerid or values.targetname or values.classname,
				}
			end
		end
	end
	for _, values in ipairs(records) do
		if values.classname == "func_ladder" or values.classname == "func_useableladder" then
			local first, second = ParseVector(values.point0), ParseVector(values.point1)
			if first and second and first.z ~= second.z then
				local top, bottom = first, second
				if top.z < bottom.z then top, bottom = bottom, top end
				local duplicatesBounds = false
				for _, ladder in ipairs(ladders) do
					if ladder.mins then
						local overlap = math.min(top.z, ladder.maxs.z) - math.max(bottom.z, ladder.mins.z)
						if overlap > 0 and BoundsDistance(Vector((top.x + bottom.x) / 2, (top.y + bottom.y) / 2, (top.z + bottom.z) / 2), ladder.mins, ladder.maxs) <= LADDER_WIDTH then
							duplicatesBounds = true
							break
						end
					end
				end
				if not duplicatesBounds then
					local midpoint = (top + bottom) / 2
					local nearest, nearestDistance
					for _, pos in ipairs(dismounts) do
						local distance = pos:DistToSqr(midpoint)
						if not nearestDistance or distance < nearestDistance then
							nearest, nearestDistance = pos, distance
						end
					end
					ladders[#ladders + 1] = {
						top = top,
						bottom = bottom,
						direction = LadderDirection(ParseVector(values.normal))
							or (nearestDistance and nearestDistance <= LADDER_DISMOUNT_REACH * LADDER_DISMOUNT_REACH
								and Cardinal(nearest - midpoint) or nil),
						id = values.hammerid or values.targetname or values.classname,
					}
				end
			end
		end
	end
	return ladders
end

local function AddWalkableSeeds(ladders)
	local up, count, hidingSpots = Vector(0, 0, 1), 0, 0
	local function Add(pos)
		navmesh.AddWalkableSeed(pos, up)
		count = count + 1
	end
	Each(SEEDS, function(ent) Add(ent:GetPos()) end)
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		for _, pos in ipairs(area:GetHidingSpots(255) or {}) do
			Add(pos)
			hidingSpots = hidingSpots + 1
		end
	end
	for _, ladder in ipairs(ladders) do
		Add(ladder.top)
		Add(ladder.bottom)
	end
	return count, hidingSpots
end

local function LadderArea(pos)
	local area = navmesh.GetNearestNavArea(pos, true, LADDER_AREA_REACH, false, false)
	if not IsValid(area) or area:GetClosestPointOnArea(pos):DistToSqr(pos) > LADDER_AREA_REACH * LADDER_AREA_REACH then
		return nil
	end
	return area
end

local function TopConnected(native)
	return IsValid(native:GetTopForwardArea()) or IsValid(native:GetTopLeftArea())
		or IsValid(native:GetTopRightArea()) or IsValid(native:GetTopBehindArea())
end

-- The area a ladder's foot stands on: the nearest below its middle, else, for
-- one hanging over a floor far beneath, the floor under it out from its wall.
local function FootArea(ladder, middle)
	local nearest = LadderArea(ladder.bottom)
	if IsValid(nearest) and nearest:GetCenter().z < middle then return nearest end
	local out = ladder.direction
	local from = Vector(ladder.bottom.x + out.x * LADDER_OVER, ladder.bottom.y + out.y * LADDER_OVER, ladder.bottom.z)
	local floor = util.TraceLine({ start = from, endpos = Vector(from.x, from.y, from.z - FLOOR_DEPTH), mask = MASK_NPCSOLID_BRUSHONLY })
	local beneath = LadderArea(floor.HitPos)
	if IsValid(beneath) and beneath:GetCenter().z < middle then return beneath end
	return nil
end

-- The engine connects a ladder as it creates it, both ways, to the areas it
-- finds; those stand (the area nearest a foot can be a nook no body walks out
-- of), but for a foot above the ladder's middle, the floor over a hanging
-- ladder, which moves to the floor beneath. An end it left gets the nearest
-- area on that side of the middle: the upper floor looked for over the wall,
-- behind the ladder.
local function ConnectLadder(native, ladder)
	local middle = (ladder.top.z + ladder.bottom.z) / 2
	local bottom = native:GetBottomArea()
	if not IsValid(bottom) or bottom:GetCenter().z >= middle then
		local foot = FootArea(ladder, middle)
		if not foot then return false end
		if IsValid(bottom) then bottom:Disconnect(native) end
		native:ConnectTo(foot)
		foot:ConnectTo(native)
	end
	if not TopConnected(native) then
		local over = ladder.direction
		local top = LadderArea(Vector(ladder.top.x - over.x * LADDER_OVER, ladder.top.y - over.y * LADDER_OVER, ladder.top.z))
		if not IsValid(top) or top == native:GetBottomArea() or top:GetCenter().z <= middle then return false end
		native:ConnectTo(top)
		top:ConnectTo(native)
	end
	return IsValid(native:GetBottomArea()) and TopConnected(native)
end

local function CreateLadders(ladders)
	local created, skipped = 0, 0
	for _, ladder in ipairs(ladders) do
		if ladder.direction then
			local native = navmesh.CreateNavLadder(ladder.top, ladder.bottom, ladder.width or LADDER_WIDTH, ladder.direction, LADDER_TOP_ADJUST)
			if not IsValid(native) then
				skipped = skipped + 1
				print("Navigation mesh: could not create ladder " .. ladder.id)
			elseif ConnectLadder(native, ladder) then
				created = created + 1
			else
				skipped = skipped + 1
				native:Remove()
				print("Navigation mesh: could not connect ladder " .. ladder.id .. " to nav areas")
			end
		else
			skipped = skipped + 1
			print("Navigation mesh: ladder " .. ladder.id .. " has no cardinal facing direction")
		end
	end
	if created > 0 then navmesh.Save() end
	return created, skipped
end

local function AnyDoorMoving()
	local moving = false
	Each(DOORS, function(door)
		if door:GetClass() == "prop_door_rotating" then
			moving = moving or PROP_DOOR_MOVING[door:GetInternalVariable("m_eDoorState")] == true
		else
			moving = moving or TOGGLE_MOVING[door:GetInternalVariable("m_toggle_state")] == true
		end
	end)
	return moving
end

-- Generates the mesh for ply (nil: the console); resume: back to Gameplay
-- mode after, when it was left for this. Whether it started.
local function Generate(ply, resume)
	if underWay or navmesh.IsGenerating() then
		Tell(ply, "Navigation mesh: already being generated")
		return false
	end
	if GetConVar("sv_gameplay_enabled"):GetBool() then
		if GetConVar("sv_gameplay_disable_sandbox"):GetBool() then
			Tell(ply, "Navigation mesh: it is generated in Sandbox mode, which sv_gameplay_disable_sandbox 1 forbids; set it to 0 first")
			return false
		end
		WS.Feature("gamemode"):Request(Gamemode.SANDBOX, Gamemode.SOURCE_BUTTON, ply)
	else
		resume = false
	end
	local ladders = Ladders()
	local seeds, hidingSpots = AddWalkableSeeds(ladders)
	underWay = true
	WS.LockSpawns("nav")
	local limits = {}
	for _, kind in ipairs(cleanup.GetTable()) do
		local limit = GetConVar("sbox_max" .. kind)
		if limit then
			limits[limit] = limit:GetString()
			limit:SetString("0")
		end
	end
	Each(DOORS, function(door)
		door:Fire("Unlock")
		door:Fire(IsFloor(door) and "Close" or "Open")
	end)
	Each(BARRIERS, function(barrier) barrier:SetNotSolid(true) end)
	local seedDetails = hidingSpots > 0 and (", including " .. hidingSpots .. " hiding spots") or ""
	local ladderDetails = #ladders > 0 and (", including endpoints of " .. #ladders .. " ladders") or ""
	Tell(ply, "Navigation mesh: opening " .. game.GetMap() .. "'s doors, then generating from " .. seeds
		.. " seeds" .. seedDetails .. ladderDetails .. "; this takes a few minutes")
	local started = CurTime()
	WS.NavProgress(Progress.OPENING)
	local giveUp, began = started + DOOR_WAIT, false
	timer.Create(POLL, 1, 0, function()
		if not began then
			if AnyDoorMoving() and CurTime() < giveUp then return end
			began = true
			Each(DOORS, function(door)
				if not IsFloor(door) then return end
				local standIn = ents.Create("func_brush")
				standIn:SetModel(door:GetModel())
				standIn:SetPos(door:GetPos())
				standIn:SetAngles(door:GetAngles())
				standIn:SetKeyValue("Solidity", "2")
				standIn:Spawn()
			end)
			navmesh.BeginGeneration()
			WS.NavProgress(Progress.GENERATING)
			return
		end
		if navmesh.IsGenerating() then return end
		timer.Remove(POLL)
		underWay = false
		local laddersCreated, laddersSkipped = CreateLadders(ladders)
		for limit, value in pairs(limits) do limit:SetString(value) end
		game.CleanUpMap()
		WS.UnlockSpawns("nav")
		WS.RepairNavStairs(WS.BridgeNavGaps)
		WS.NavProgress(Progress.DONE, navmesh.GetNavAreaCount())
		local ladderSummary = #ladders > 0 and (", " .. laddersCreated .. " ladders created, " .. laddersSkipped .. " skipped") or ""
		Tell(ply, "Navigation mesh: done, " .. navmesh.GetNavAreaCount() .. " areas" .. ladderSummary
			.. ", saved as maps/" .. game.GetMap() .. ".nav; the map was reset")
		if resume then WS.Feature("gamemode"):Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_CONSOLE, nil) end
	end)
	return true
end

concommand.Add("mp_nav_generate", function(ply)
	if not WS.Can(ply, system.permissions.RULES) then
		Tell(ply, "Navigation mesh: you may not generate it")
		return
	end
	Generate(ply, false)
end, nil, "Generate this map's navigation mesh from its seeds and ladder entities, its doors open (admins); takes a few minutes and resets the map")

-- The map's ladders built again over the mesh as it stands, its areas kept and
-- the map not reset; saved, as a generation saves them. A ladder removed does
-- not go at once, its areas holding it till then, so the new ones wait.
concommand.Add("mp_nav_ladders", function(ply)
	if not WS.Can(ply, system.permissions.RULES) then
		Tell(ply, "Navigation mesh: you may not build its ladders")
		return
	end
	if underWay or navmesh.IsGenerating() then
		Tell(ply, "Navigation mesh: a generation is under way, and builds them")
		return
	end
	local removed = {}
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		for _, ladder in ipairs(area:GetLadders()) do
			if not removed[ladder] then
				removed[ladder] = true
				ladder:Remove()
			end
		end
	end
	timer.Create(LADDERS_REBUILD, LADDERS_REMOVED_WAIT, 1, function()
		local ladders = Ladders()
		local created, skipped = CreateLadders(ladders)
		Tell(ply, "Navigation mesh: " .. created .. " ladders built, " .. skipped .. " skipped of the map's " .. #ladders)
	end)
end, nil, "Build this map's ladders again over its navigation mesh and save it, keeping its areas and not resetting the map (admins)")

-- The idle server's own run (ws/sv_idle.lua).
hook.Add("WSServerIdle", "ws_nav", function()
	if WS.NavMeshUsable() or underWay or navmesh.IsGenerating() then return end
	if Generate(nil, true) then print("Navigation mesh: the server is idle and " .. game.GetMap() .. " has none; generating one") end
end)
