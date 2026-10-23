-- The nodegraph feature's controller: makes an AI node graph for the map
-- from its nav mesh (foundation.nodegraph), checks each link with hull
-- traces, writes the engine's .ain file, and shows it to admins.
--
-- GMod's Lua can only write under garrysmod/data, and the engine reads a
-- map's graph only from maps/graphs/<map>.ain, once, as the map loads (and
-- only when its map version matches and it is newer than the .bsp,
-- CAI_NetworkManager::IsAIFileCurrent). So a generated graph is written to
-- data/sandcastle/nodegraphs/<map>.dat, and put in place by hand:
-- copied to garrysmod/maps/graphs/<map>.ain, then the map reloaded.
--
-- Nodes (after navmesh_node_mapper, github.com/riggs9162/navmesh_node_mapper):
-- the nav mesh's hiding spots first, as HL2's cover search tests plain
-- nodes for cover from its enemy, then the centres of the nav areas a
-- soldier can walk (no crouch or jump areas), largest first, spaced apart;
-- the spacing grows until the graph fits the engine's node limit. Links:
-- each node's nearest within LINK_RANGE, kept for each hull whose box
-- sweeps from one to the other above step height, over floor that never
-- rises or falls more than a step between samples.
local Graph = nodegraph

local Controller = {
	job = nil, -- the generation coroutine while it runs
	graph = nil, -- the graph last generated this map: { file graph, spacing }
	installed = nil, -- the installed graph, read for the overlay
}

local DATA_DIR = "sandcastle/nodegraphs"
local MAX_NODES = GetConVar("ws_nodegraph_max_nodes") -- ws/sh_nodegraph.lua

local SPACING_START, SPACING_GROW = 96, 1.25
local LINK_RANGE, LINKS_PER_NODE = 512, 16
local BRIDGES_PER_NODE = 4
-- The floor is sampled every FLOOR_SAMPLE units along a link, finer than
-- a stair's tread, so each sample rises at most one step; the engine's own
-- builder steps a hull every 16 (HULL_TEST_STEP_SIZE).
local STEP, FLOOR_SAMPLE, FLOOR_SLOPE, FLOOR_PROBE = 18, 12, 0.7, 64
local HIDING_IN_COVER = 1
local HIDING_BONUS = 1e9 -- hiding spots are picked before any area
local NAV_MESH_CROUCH, NAV_MESH_JUMP = 1, 2
local BUDGET = 0.004 -- seconds of each tick the generation may take

-- Doors are left out of every trace: a graph links through them whether
-- they stand open or shut, as HL2's maps do, and the engine finds a door
-- shut when an NPC walks it.
-- A door's visible part is often a model parented to an invisible
-- func_door (a grate, a shutter), so what rides on a door counts as it.
-- A spawn room's forcefield (func_respawnroomvisualizer) is left out too:
-- it stops only the other team's players, and only while a round runs.
local DOOR_CLASSES = {
	func_door = true, func_door_rotating = true, prop_door_rotating = true, func_movelinear = true,
	func_respawnroomvisualizer = true,
}
local PARENT_DEPTH = 4

local function NotDoor(ent)
	for _ = 1, PARENT_DEPTH do
		if not IsValid(ent) then return true end
		if DOOR_CLASSES[ent:GetClass()] then return false end
		ent = ent:GetParent()
	end
	return true
end

local function Point(v) return { x = v.x, y = v.y, z = v.z } end
local function ToVector(p) return Vector(p.x, p.y, p.z) end

function Controller:DataPath() return DATA_DIR .. "/" .. game.GetMap() .. ".dat" end
function Controller:InstalledPath() return "maps/graphs/" .. game.GetMap() .. ".ain" end

local function Tell(ply, text)
	text = "Node graph: " .. text
	if IsValid(ply) then ply:ChatPrint(text) end
	print(text)
end

-- Generation --------------------------------------------------------------------------

local deadline = 0

-- Inside the job: hand the tick back once its time is spent.
local function Pause()
	if SysTime() >= deadline then coroutine.yield() end
end

local function FloorBelow(pos)
	local tr = util.TraceLine({
		start = pos + Vector(0, 0, STEP * 2),
		endpos = pos - Vector(0, 0, FLOOR_PROBE),
		mask = MASK_NPCSOLID_BRUSHONLY,
		filter = NotDoor,
	})
	if tr.StartSolid or not tr.Hit or tr.HitNormal.z < FLOOR_SLOPE then return nil end
	return tr.HitPos
end

-- A seam where the ground changes height (a stair's top or bottom): the
-- middle of the edge two walkable areas share, where either area slopes
-- (its corners rise SLOPE_RISE or more) or their centres differ by more
-- than a step. Long stairs have no node near their ends otherwise, and
-- their top and bottom lie beyond a link's reach of each other.
local SLOPE_RISE = 24
local SEAM_BONUS = HIDING_BONUS / 2 -- after cover spots, before any area

local function Walkable(area)
	return bit.band(area:GetAttributes(), NAV_MESH_CROUCH + NAV_MESH_JUMP) == 0 and not area:IsUnderwater()
end

local function Slopes(area)
	local low, high = math.huge, -math.huge
	for corner = 0, 3 do
		local z = area:GetCorner(corner).z
		low, high = math.min(low, z), math.max(high, z)
	end
	return high - low >= SLOPE_RISE
end

local function Rect(area)
	local extent = area:GetExtentInfo()
	return { lo = { x = extent.lo.x, y = extent.lo.y }, hi = { x = extent.hi.x, y = extent.hi.y } }
end

local function Seams(area, list, seen)
	for dir = 0, 3 do
		for _, other in ipairs(area:GetAdjacentAreasAtSide(dir) or {}) do
			local key = math.min(area:GetID(), other:GetID()) .. ":" .. math.max(area:GetID(), other:GetID())
			if not seen[key] and Walkable(other)
				and (Slopes(area) or Slopes(other) or math.abs(area:GetCenter().z - other:GetCenter().z) > STEP) then
				seen[key] = true
				local x, y = Graph.SeamPoint(Rect(area), Rect(other), dir)
				local z = math.max(area:GetZ(Vector(x, y, 0)), other:GetZ(Vector(x, y, 0)))
				local floor = FloorBelow(Vector(x, y, z))
				if floor then list[#list + 1] = { pos = Point(floor), size = SEAM_BONUS } end
			end
		end
	end
end

-- The candidates: hiding spots, seams where the ground changes height and
-- walkable area centres, on the floor.
local function Candidates()
	local list, seen = {}, {}
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		if Walkable(area) then
			Seams(area, list, seen)
			local floor = FloorBelow(area:GetCenter())
			if floor then list[#list + 1] = { pos = Point(floor), size = area:GetSizeX() * area:GetSizeY() } end
			for _, spot in ipairs(area:GetHidingSpots(HIDING_IN_COVER) or {}) do
				local spotFloor = FloorBelow(spot)
				if spotFloor then list[#list + 1] = { pos = Point(spotFloor), size = HIDING_BONUS, cover = true } end
			end
		end
		Pause()
	end
	return list
end

-- CAI_NetworkBuilder::InitGroundNodePosition: per hull, where a pancake of
-- the hull lands below the node.
local function Offsets(origin)
	local offsets = {}
	for hull = 0, Graph.NUM_HULLS - 1 do
		local box = Graph.HULLS[hull]
		local mins, maxs = Vector(box.mins[1], box.mins[2], box.mins[3]), Vector(box.maxs[1], box.maxs[2], box.mins[3])
		local start = origin + Vector(0, 0, 0.1 - mins.z)
		local tr = util.TraceHull({ start = start, endpos = start - Vector(0, 0, 384), mins = mins, maxs = maxs, mask = MASK_NPCSOLID_BRUSHONLY, filter = NotDoor })
		offsets[hull] = tr.StartSolid and (-mins.z + 0.1) or (tr.HitPos.z - origin.z + 0.1)
	end
	return offsets
end

-- The floor between a and b as an HL2 NPC walks it: the points found every
-- FLOOR_SAMPLE units, a first, b last; or nil where it rises or falls more
-- than a step between samples, or has no floor.
local function FloorPath(a, b)
	local from, to = ToVector(a), ToVector(b)
	local steps = math.max(1, math.ceil(from:Distance(to) / FLOOR_SAMPLE))
	local path, lastZ = { from }, from.z
	for i = 1, steps do
		local floor = FloorBelow(LerpVector(i / steps, from, to))
		if not floor or math.abs(floor.z - lastZ) > STEP then return nil end
		lastZ = floor.z
		path[#path + 1] = floor
	end
	return path
end

-- Whether the hull's box, above step height, sweeps from `from` to `to`.
local function Sweeps(box, from, to)
	return not util.TraceHull({
		start = from + Vector(0, 0, STEP),
		endpos = to + Vector(0, 0, STEP),
		mins = Vector(box.mins[1], box.mins[2], 0),
		maxs = Vector(box.maxs[1], box.maxs[2], math.max(box.maxs[3] - STEP, 1)),
		mask = MASK_NPCSOLID_BRUSHONLY,
		filter = NotDoor,
	}).Hit
end

-- Whether the hull walks the floor path: in one sweep where the ground is
-- flat enough, else leg by leg along the floor, every FOLLOW_STRIDE
-- samples, as the engine's builder steps its hull over the ground; a
-- straight line up a stair to a landing set back from its top runs
-- shallower than the stair and cuts through its last steps.
local FOLLOW_STRIDE = 2

local function Walks(box, path)
	if Sweeps(box, path[1], path[#path]) then return true end
	local last = 1
	for i = 1 + FOLLOW_STRIDE, #path + FOLLOW_STRIDE - 1, FOLLOW_STRIDE do
		local j = math.min(i, #path)
		if not Sweeps(box, path[last], path[j]) then return false end
		last = j
	end
	return true
end

-- The hulls that can walk from a to b: CAP_MOVE_GROUND per hull, or nil.
local function Moves(a, b)
	local path = FloorPath(a, b)
	if not path then return nil end
	local moves, any = {}, false
	for hull = 0, Graph.NUM_HULLS - 1 do
		local box = Graph.HULLS[hull]
		moves[hull] = 0
		if box.ground and Walks(box, path) then
			moves[hull] = Graph.CAP_MOVE_GROUND
			any = true
		end
	end
	return any and moves or nil
end

function Controller:Build(ply)
	local candidates = Candidates()
	if #candidates == 0 then return Tell(ply, "this map has no nav mesh to build from") end
	local limit, spacing = MAX_NODES:GetInt(), SPACING_START
	local chosen = Graph.PickNodes(candidates, spacing, math.huge)
	while #chosen > limit do
		spacing = spacing * SPACING_GROW
		chosen = Graph.PickNodes(candidates, spacing, math.huge)
		Pause()
	end
	Tell(ply, string.format("%d nodes %d units apart; testing links...", #chosen, math.floor(spacing)))
	local positions, nodes, covers = {}, {}, 0
	for i, candidate in ipairs(chosen) do
		positions[i] = candidate.pos
		local origin = ToVector(candidate.pos) + Vector(0, 0, Graph.NODE_HEIGHT)
		nodes[i] = { pos = Point(origin), yaw = 0, offsets = Offsets(origin), type = Graph.NODE_GROUND, info = 0 }
		if candidate.cover then covers = covers + 1 end
		Pause()
	end
	local links = {}
	for _, link in ipairs(Graph.Candidates(positions, LINK_RANGE, LINKS_PER_NODE)) do
		local moves = Moves(positions[link.a], positions[link.b])
		if moves then
			link.moves = moves
			links[#links + 1] = link
		end
		Pause()
	end
	-- join what the nearest links left apart (a wall's far side, a doorway)
	local zones = Graph.Zones(#nodes, links)
	local bridged = 0
	for _, link in ipairs(Graph.Bridges(positions, zones, Graph.MAX_LINK_DISTANCE, BRIDGES_PER_NODE)) do
		local moves = Moves(positions[link.a], positions[link.b])
		if moves then
			link.moves = moves
			links[#links + 1] = link
			bridged = bridged + 1
		end
		Pause()
	end
	table.sort(links, function(x, y) return x.distance < y.distance end)
	links = Graph.CapLinks(links, Graph.MAX_NODE_LINKS)
	zones = Graph.Zones(#nodes, links)
	local zoneCount = {}
	for i, node in ipairs(nodes) do
		node.zone = zones[i]
		zoneCount[zones[i]] = true
	end
	local graph = { mapVersion = game.GetMapVersion(), nodes = nodes, links = links }
	self.graph = { file = graph, spacing = spacing, covers = covers, zones = table.Count(zoneCount) }
	file.CreateDir(DATA_DIR)
	local out = file.Open(self:DataPath(), "wb", "DATA")
	if not out then return Tell(ply, "could not write data/" .. self:DataPath()) end
	out:Write(Graph.Encode(graph))
	out:Close()
	Tell(ply, string.format("%d nodes (%d at cover spots), %d links (%d joining zones), %d zones. Written to garrysmod/data/%s",
		#nodes, covers, #links, bridged, self.graph.zones, self:DataPath()))
	Tell(ply, "to use it: copy that file to garrysmod/" .. self:InstalledPath() .. " and reload the map")
end

-- Returns true, or false and why not.
function Controller:Generate(ply)
	if self.job then return false, "already generating" end
	if not navmesh.IsLoaded() or navmesh.GetNavAreaCount() == 0 then return false, "this map has no nav mesh" end
	self.job = coroutine.create(function() self:Build(ply) end)
	self.jobOwner = ply
	Tell(ply, "generating from " .. navmesh.GetNavAreaCount() .. " nav areas...")
	return true
end

function Controller:Think()
	if not self.job then return end
	deadline = SysTime() + BUDGET
	local ok, err = coroutine.resume(self.job)
	if not ok then
		Tell(self.jobOwner, "generation failed: " .. tostring(err))
		self.job = nil
	elseif coroutine.status(self.job) == "dead" then
		self.job = nil
	end
end

-- Destroying and status -------------------------------------------------------------------

function Controller:Destroy(ply)
	if self.job then return false, "wait for the generation to finish" end
	local had = file.Exists(self:DataPath(), "DATA")
	file.Delete(self:DataPath())
	self.graph = nil
	Tell(ply, had and ("deleted garrysmod/data/" .. self:DataPath()) or "no generated graph to delete")
	if file.Exists(self:InstalledPath(), "GAME") then
		Tell(ply, "an installed graph remains at " .. self:InstalledPath() .. "; Lua cannot delete it, remove it by hand")
	end
	return true
end

-- The installed graph, read (the engine loaded it if its map version
-- matched, as the map loaded), or nil and why.
function Controller:Installed(headerOnly)
	local path = self:InstalledPath()
	if not file.Exists(path, "GAME") then return nil, "none installed" end
	local handle = file.Open(path, "rb", "GAME")
	if not handle then return nil, "unreadable" end
	local data = handle:Read(handle:Size())
	handle:Close()
	return Graph.Decode(data or "", headerOnly)
end

function Controller:Status(ply)
	local lines = {}
	if self.job then lines[#lines + 1] = "generating..." end
	local generated = self.graph
	if generated then
		lines[#lines + 1] = string.format("generated this map: %d nodes (%d cover), %d links, %d zones, spacing %d",
			#generated.file.nodes, generated.covers, #generated.file.links, generated.zones, math.floor(generated.spacing))
	elseif file.Exists(self:DataPath(), "DATA") then
		lines[#lines + 1] = "generated earlier: garrysmod/data/" .. self:DataPath()
	else
		lines[#lines + 1] = "none generated"
	end
	local installed, why = self:Installed(true)
	if installed then
		local fits = installed.version == Graph.VERSION and installed.mapVersion == game.GetMapVersion()
		lines[#lines + 1] = string.format("installed: %d nodes, map version %d (this map %d): %s", installed.nodeCount,
			installed.mapVersion, game.GetMapVersion(), fits and "the engine loads it" or "out of date, the engine ignores it")
	else
		lines[#lines + 1] = "installed: " .. why
	end
	for _, line in ipairs(lines) do Tell(ply, line) end
	return true
end

-- The overlay -------------------------------------------------------------------------------

local DEBUG_INTERVAL, DEBUG_RANGE, DEBUG_MAX_NODES = 1, 1500, 400
local DEBUG_MAX_LINKS = 2 ^ 16 - 1 -- game_nodegraph_debug's count (ws/sh_nodegraph.lua)

function Controller:ToggleDebug(ply)
	ply.wsNodegraphDebug = not ply.wsNodegraphDebug
	if ply.wsNodegraphDebug and not self.graph and not self.installed then
		self.installed = self:Installed()
	end
	Tell(ply, "overlay " .. (ply.wsNodegraphDebug and "on" or "off"))
	return true
end

-- The generated graph, else the installed one: the nodes near ply and the
-- links between them.
function Controller:SendDebug(ply)
	local graph = (self.graph and self.graph.file) or self.installed
	local eye = ply:GetPos()
	local sent, index = {}, {}
	if graph then
		for i, node in ipairs(graph.nodes) do
			if #sent >= DEBUG_MAX_NODES then break end
			if eye:DistToSqr(ToVector(node.pos)) <= DEBUG_RANGE * DEBUG_RANGE then
				sent[#sent + 1] = node
				index[i] = #sent
			end
		end
	end
	local links = {}
	for _, link in ipairs(graph and graph.links or {}) do
		if index[link.a] and index[link.b] and #links < DEBUG_MAX_LINKS then
			links[#links + 1] = {
				a = index[link.a],
				b = index[link.b],
				human = (link.moves and link.moves[0] or 0) ~= 0,
			}
		end
	end
	local nodes = {}
	for i, node in ipairs(sent) do
		nodes[i] = {
			pos = ToVector(node.pos),
			zone = node.zone or 0,
		}
	end
	WS.Events.Fire("game_nodegraph_debug", {
		source = self.graph and "generated" or (graph and "installed" or "none"),
		nodes = nodes,
		links = links,
	}, ply)
end

local nextDebug = 0
hook.Add("Think", "ws_nodegraph", function()
	Controller:Think()
	local now = CurTime()
	if now < nextDebug then return end
	nextDebug = now + DEBUG_INTERVAL
	for _, ply in ipairs(player.GetAll()) do
		if ply.wsNodegraphDebug then Controller:SendDebug(ply) end
	end
end)

return Controller
