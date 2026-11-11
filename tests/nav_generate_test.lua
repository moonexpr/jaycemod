-- mp_nav_generate (sv_nav.lua): an admin, or the server console,
-- builds the map's navigation mesh. GMod's generator walks out from seeds,
-- and TF2 maps spawn players at info_player_teamspawn, which it does not
-- seed from: every spawn point and control point is a seed. It walks only
-- what stands in place, so every door, gate and bridge is opened first,
-- spawn barriers made passable, and the map reset when it is done. Run
-- against fakes of concommand, ents, navmesh, timer and game.
local T = dofile ("tests/harness.lua")
local Gamemode = system.gamemode

local function Ent (class, x, y, z)
	return { class = class, GetClass = function () return class end, GetPos = function () return { x = x, y = y, z = z } end }
end

local function Player (admin)
	local p = { said = {} }
	function p:IsAdmin () return admin end
	function p:ChatPrint (text) self.said [#self.said + 1] = text end
	return p
end

-- A func_door (m_toggle_state: 0 open, 1 closed, 2 opening, 3 closing) that
-- takes `travel` polls to move once told to; `size` its brush (default a
-- door's: 64 wide, 8 deep, 128 tall).
local function Door (class, travel, size)
	local d = Ent (class, 0, 0, 0)
	d.state, d.inputs, d.travel = 1, {}, travel or 0
	size = size or { x = 64, y = 8, z = 128 }
	function d:GetModel () return "*7" end
	function d:GetPos () return { x = 10, y = 20, z = 30 } end
	function d:GetAngles () return { p = 0, y = 90, r = 0 } end
	function d:OBBMins () return { x = -size.x / 2, y = -size.y / 2, z = 0 } end
	function d:OBBMaxs () return { x = size.x / 2, y = size.y / 2, z = size.z } end
	function d:Fire (input)
		self.inputs [#self.inputs + 1] = input
		if input == "Open" then self.state = self.travel > 0 and 2 or 0 end
		if input == "Close" then self.state = self.travel > 0 and 3 or 1 end
	end
	function d:GetInternalVariable (name) return name == "m_toggle_state" and self.state or nil end
	function d:Tick ()
		if self.state < 2 then return end
		self.travel = self.travel - 1
		if self.travel <= 0 then self.state = self.state == 2 and 0 or 1 end
	end
	return d
end

-- A prop_door_rotating (m_eDoorState: 0 closed, 1 opening, 2 open, 3 closing).
local function PropDoor ()
	local d = Ent ("prop_door_rotating", 0, 0, 0)
	d.state, d.inputs = 0, {}
	function d:OBBMins () return { x = -27, y = -2, z = 0 } end
	function d:OBBMaxs () return { x = 27, y = 2, z = 108 } end
	function d:Fire (input) self.inputs [#self.inputs + 1] = input if input == "Open" then self.state = 2 end end
	function d:GetInternalVariable (name) return name == "m_eDoorState" and self.state or nil end
	function d:Tick () end
	return d
end

local function Barrier ()
	local b = Ent ("func_respawnroomvisualizer", 0, 0, 0)
	b.solid = true
	function b:SetNotSolid (off) self.solid = not off end
	return b
end

local function BspEntity (class, values)
	local entity = { { key = "classname", value = class } }
	for key, value in pairs (values or {}) do entity [#entity + 1] = { key = key, value = value } end
	return entity
end

-- A vector with the arithmetic the seam sweep does.
local Vec = {}
Vec.__index = Vec
local function V (x, y, z) return setmetatable ({ x = x, y = y, z = z }, Vec) end
function Vec:DistToSqr (other)
	local x, y, z = self.x - other.x, self.y - other.y, self.z - other.z
	return x * x + y * y + z * z
end
Vec.__add = function (a, b) return V (a.x + b.x, a.y + b.y, a.z + b.z) end
Vec.__sub = function (a, b) return V (a.x - b.x, a.y - b.y, a.z - b.z) end
Vec.__div = function (a, n) return V (a.x / n, a.y / n, a.z / n) end

local GENERATE_POLL = "ws_nav_generate"

local function load (t)
	local s = { commands = {}, seeds = {}, timers = {}, delays = {}, cleaned = 0, now = 0, hooks = {}, sweeps = {}, ran = {} }
	s.humans = t.humans or {}
	s.mapEntities = t.mapEntities or {}
	s.ladders, s.lifecycle, s.printed = {}, {}, {}
	s.ladderAreas = t.ladderAreas or {}
	-- the mesh's areas (NavArea fakes) and what a sweep across a seam hits:
	-- trace(t) -> { Hit, StartSolid }
	s.navAreas = t.navAreas or {}
	s.trace = t.trace or function (tr) return { Hit = tr.endpos.z < tr.start.z, StartSolid = false } end
	s.nav = { generating = false, areas = t.areas or 0, began = 0 }
	s.convars =
	{
		sv_gameplay_enabled = t.gameplay and "1" or "0",
		sv_gameplay_disable_sandbox = t.noSandbox and "1" or "0"
	}
	for name, value in pairs (t.limits or {}) do s.convars [name] = value end
	s.requests, s.sent, s.created = {}, {}, {}
	s.ramps, s.stairAreas = {}, t.stairAreas
	s.stages = {}
	s.locks = {}
	s.ws =
	{
		require = T.require,
		LockSpawns = function (lock) s.locks [#s.locks + 1] = "lock " .. lock end,
		UnlockSpawns = function (lock) s.locks [#s.locks + 1] = "unlock " .. lock end,
		MapFile = function (names)
			if names [1] == "BRUSHES" then return { BRUSHES = t.brushes or {} } end
			T.eq (names [1], "ENTITIES")
			return { ENTITIES = s.mapEntities }
		end,
		-- The server console (nil) may; a player as their admin flag says.
		Can = function (ply) return ply == nil or ply:IsAdmin () end,
		NavProgress = function (stage, areas, extra)
			s.stages [#s.stages + 1] = { stage = stage, areas = areas, extra = extra }
		end,
		Feature = function (name)
			assert (name == "gamemode", name)
			return
			{
				Request = function (_, want, source, requester)
					s.requests [#s.requests + 1] = want
					s.convars.sv_gameplay_enabled = want == Gamemode.GAMEPLAY and "1" or "0"
					return true
				end
			}
		end
	}
	local env = setmetatable (
		{
			GetConVar = function (name)
				if s.convars [name] == nil then return nil end
				return
				{
					GetBool = function () return s.convars [name] ~= "0" end,
					GetString = function () return s.convars [name] end,
					SetString = function (_, v) s.convars [name] = v end
				}
			end,
			cleanup = { GetTable = function () return t.cleanups or {} end },
			WS = s.ws,
			concommand = { Add = function (name, fn) s.commands [name] = fn end },
			ents =
			{
				Create = function (class)
					local e = { class = class, keys = {}, spawned = false }
					function e:SetModel (m) self.model = m end
					function e:SetPos (p) self.pos = p end
					function e:SetAngles (a) self.angles = a end
					function e:SetKeyValue (k, v) self.keys [k] = v end
					function e:Spawn () self.spawned = true end
					s.created [#s.created + 1] = e
					return e
				end,
				GetAll = function () return t.entities or {} end,
				FindByClass = function (class)
					local found = {}
					for _, e in ipairs (t.entities or {}) do if e.class == class then found [#found + 1] = e end end
					return found
				end
			},
			navmesh =
			{
				AddWalkableSeed = function (pos, normal) s.seeds [#s.seeds + 1] = { pos = pos, normal = normal } end,
				GetNearestNavArea = function (pos, _, maxDistance)
					local nearest, distance
					for _, area in ipairs (s.ladderAreas) do
						local candidate = area:GetClosestPointOnArea (pos)
						local candidateDistance = candidate:DistToSqr (pos)
						if not distance or candidateDistance < distance then
							nearest, distance = area, candidateDistance
						end
					end
					return distance and distance <= maxDistance * maxDistance and nearest or nil
				end,
				CreateNavLadder = function (top, bottom, width, direction, topAdjust)
					local ladder = { top = top, bottom = bottom, width = width, direction = direction, topAdjust = topAdjust }
					local middle = (top.z + bottom.z) / 2
					function ladder:ConnectTo (area)
						if area:GetCenter ().z > middle then self.topArea = area else self.bottomArea = area end
					end
					function ladder:GetBottomArea () return self.bottomArea end
					function ladder:GetTopForwardArea () return self.topArea end
					function ladder:GetTopLeftArea () return nil end
					function ladder:GetTopRightArea () return nil end
					function ladder:GetTopBehindArea () return nil end
					function ladder:Remove () self.removed = true end
					s.ladders [#s.ladders + 1] = ladder
					s.lifecycle [#s.lifecycle + 1] = "ladder"
					-- the engine connects what it finds as it creates a ladder
					if t.engineConnects then t.engineConnects (ladder) end
					return ladder
				end,
				FindInBox = function (mins, maxs)
					s.stairBox = { mins = mins, maxs = maxs }
					return s.stairAreas or {}
				end,
				GetNavAreaByID = function (id)
					for _, area in ipairs (s.stairAreas or {}) do
						if area:GetID () == id then return area end
					end
				end,
				CreateNavArea = function ()
					local ramp = { attributes = 0, links = {} }
					function ramp:SetCorner () end
					function ramp:AddAttributes (attributes) self.attributes = attributes end
					function ramp:ConnectTo (other) self.links [other] = true end
					s.ramps [#s.ramps + 1] = ramp
					s.lifecycle [#s.lifecycle + 1] = "ramp"
					return ramp
				end,
				Save = function () s.lifecycle [#s.lifecycle + 1] = "save" end,
				BeginGeneration = function () s.nav.began = s.nav.began + 1 s.nav.generating = true end,
				IsGenerating = function () return s.nav.generating end,
				IsLoaded = function () return s.nav.areas > 0 end,
				GetNavAreaCount = function () return s.nav.areas end,
				GetAllNavAreas = function () return s.navAreas end
			},
			hook =
			{
				Add = function (event, name, fn)
					local before = s.hooks [event]
					-- as GMod's: the first hook to answer decides
					s.hooks [event] = function (...)
						local answer = before and before (...)
						if answer ~= nil then return answer end
						return fn (...)
					end
				end,
				Run = function (event) s.ran [#s.ran + 1] = event end
			},
			util =
			{
				TraceHull = function (tr) s.sweeps [#s.sweeps + 1] = tr return s.trace (tr) end,
				TraceLine = function (tr)
					return
					{
						Hit = t.wall ~= nil and t.wall (tr.start),
						StartSolid = false,
						HitPos = t.floorZ and V (tr.start.x, tr.start.y, t.floorZ) or tr.endpos
					}
				end
			},
			MASK_PLAYERSOLID = 1, MASK_PLAYERSOLID_BRUSHONLY = 2, MASK_NPCSOLID = 3, MASK_NPCSOLID_BRUSHONLY = 4,
			timer =
			{
				Create = function (name, delay, reps, fn)
					s.timers [name], s.delays [name] = fn, delay
				end,
				Remove = function (name) s.timers [name] = nil end,
				Simple = function (_, fn) s.nextTick = fn end
			},
			NAV_MESH_STAIRS = 4096,
			player = { GetHumans = function () return s.humans end },
			game =
			{
				GetMap = function () return "cp_steel" end,
				CleanUpMap = function () s.cleaned = s.cleaned + 1 s.lifecycle [#s.lifecycle + 1] = "cleanup" end
			},
			CurTime = function () return s.now end,
			Vector = V,
			IsValid = function (p) return p ~= nil end,
			print = function (...) s.printed [#s.printed + 1] = table.concat ({ ... }, " ") end
		}, { __index = _G })
	setfenv (assert (loadfile ("addons/sandcastle/gamemodes/sandcastle/gamemode/sv_nav.lua")), env) ()
	-- one poll of its timer, a second on, the doors moving meanwhile
	function s.Poll ()
		s.now = s.now + 1
		for _, e in ipairs (t.entities or {}) do if e.Tick then e:Tick () end end
		local poll = s.timers [GENERATE_POLL]
		if poll then poll () end
	end
	return s
end

local SPAWNS =
{
	Ent ("info_player_teamspawn", 1, 2, 3),
	Ent ("info_player_teamspawn", 4, 5, 6),
	Ent ("info_player_start", 7, 8, 9),
	Ent ("team_control_point", 10, 11, 12),
	Ent ("prop_physics", 0, 0, 0)
}

local function LadderArea (z)
	local area = { center = V (0, 0, z), ladders = {} }
	function area:GetCenter () return self.center end
	function area:GetClosestPointOnArea (pos) return V (pos.x, pos.y, self.center.z) end
	function area:ConnectTo (ladder) self.ladders [ladder] = true end
	function area:Disconnect (ladder) self.ladders [ladder] = nil end
	return area
end

T.test ("an admin's mp_nav_generate seeds every spawn and control point, facing up, and begins", function ()
	local s = load ({ entities = SPAWNS })
	local admin = Player (true)
	s.commands.mp_nav_generate (admin)
	s.Poll ()
	T.eq (#s.seeds, 4, "three spawns and a point")
	for _, seed in ipairs (s.seeds) do T.eq (seed.normal.z, 1, "facing up") end
	T.eq (s.nav.began, 1, "generation began")
	T.eq (#admin.said >= 1, true, "told it began")
end)

T.test ("nav generation seeds existing hiding spots and BSP ladder endpoints, then saves connected ladders", function ()
	local spots = { V (100, 200, 30), V (300, 400, 50) }
	local hidingArea =
	{
		GetHidingSpots = function (_, kind)
			T.eq (kind, 255, "all hiding spot types")
			return spots
		end
	}
	local mapEntities =
	{
		BspEntity ("func_useableladder",
			{
				point0 = "32 0 128",
				point1 = "0 0 0",
				normal = "0 1 0",
				hammerid = "sloped"
			}
		),
		BspEntity ("func_useableladder",
			{
				point0 = "0 0 128",
				point1 = "0 0 0",
				origin = "-32 0 36",
				hammerid = "vertical"
			}
		),
		BspEntity ("info_ladder",
			{
				["mins.x"] = "-2932.00",
				["mins.y"] = "-1058.00",
				["mins.z"] = "-144.00",
				["maxs.x"] = "-2908.00",
				["maxs.y"] = "-1056.00",
				["maxs.z"] = "-16.00",
				hammerid = "legacy"
			}
		),
		BspEntity ("info_ladder_dismount", { origin = "-2920 -1033 -12", hammerid = "dismount" }),
		BspEntity ("info_ladder_dismount", { origin = "32 0 64", hammerid = "endpoint-dismount" }),
		BspEntity ("func_useableladder",
			{
				point0 = "-2920 -1076 -151.64",
				point1 = "-2920 -1076 -54.36",
				origin = "-2920 -1076 -103",
				hammerid = "legacy-duplicate"
			}
		)
	}
	local bottom, top = LadderArea (-140), LadderArea (-20)
	local ground, upper = LadderArea (0), LadderArea (128)
	local s = load (
		{
			entities = SPAWNS,
			navAreas = { hidingArea },
			mapEntities = mapEntities,
			ladderAreas = { bottom, top, ground, upper }
		}
	)
	s.commands.mp_nav_generate (Player (true))
	s.Poll ()
	T.eq (#s.seeds, 12, "four map seeds, two hiding spots and endpoints for three unique ladders")
	T.eq (s.seeds [5].pos, spots [1])
	T.eq (s.seeds [6].pos, spots [2])
	T.eq (s.seeds [7].pos.z, -16, "the legacy ladder's top bound")
	T.eq (s.seeds [8].pos.z, -144, "the legacy ladder's bottom bound")
	T.eq (s.seeds [9].pos.z, 128, "the first endpoint ladder's top")
	T.eq (s.seeds [10].pos.z, 0, "the first endpoint ladder's bottom")
	T.eq (s.seeds [11].pos.z, 128, "the second endpoint ladder's top")
	T.eq (s.seeds [12].pos.z, 0, "the second endpoint ladder's bottom")
	T.eq (s.ladders [1], nil, "ladder objects wait until the generated areas exist")

	s.navAreas = {}
	s.nav.generating, s.nav.areas = false, 20
	s.Poll ()
	T.eq (#s.ladders, 3)
	T.eq (s.ladders [1].topAdjust, 128)
	T.eq (s.ladders [1].width, 24)
	T.eq (s.ladders [1].direction.y, 1, "the closest legacy dismount identifies the ladder's facing")
	T.eq (s.ladders [1].top.z, -16)
	T.eq (s.ladders [1].bottom.z, -144)
	T.eq (s.ladders [2].width, 32)
	T.eq (s.ladders [2].direction.y, 1, "an explicit ladder normal gives its cardinal facing")
	T.eq (s.ladders [3].direction.x, 1, "the nearest dismount gives a vertical ladder's facing")
	T.eq (s.ladders [1].bottomArea, bottom, "the ladder connects to its bottom area")
	T.eq (s.ladders [1].topArea, top, "the ladder connects to its top area")
	T.eq (bottom.ladders [s.ladders [1]], true, "the bottom area connects back to the ladder")
	T.eq (top.ladders [s.ladders [1]], true, "the top area connects back to the ladder")
	T.eq (s.ladders [2].bottomArea, ground, "endpoint ladders attach to the lower area")
	T.eq (s.ladders [2].topArea, upper, "endpoint ladders attach to the upper area")
	T.eq (table.concat (s.lifecycle, ","), "ladder,ladder,ladder,save,cleanup", "connected ladders are saved before map cleanup")
end)

T.test ("ladders without nearby areas are skipped and not saved", function ()
	local mapEntities =
	{
		BspEntity ("func_useableladder",
			{
				point0 = "0 0 128",
				point1 = "0 0 0",
				normal = "0 1 0",
				hammerid = "unconnected"
			}
		)
	}
	local s = load ({ entities = SPAWNS, mapEntities = mapEntities })
	s.commands.mp_nav_generate (nil)
	s.Poll ()
	s.nav.generating, s.nav.areas = false, 20
	s.Poll ()
	T.eq (#s.ladders, 1, "the native ladder was attempted")
	T.eq (s.ladders [1].removed, true, "the unattached ladder is removed")
	T.eq (table.concat (s.lifecycle, ","), "ladder,cleanup", "no invalid nav mesh is saved")
	local reported = false
	for _, message in ipairs (s.printed) do
		if message:find ("could not connect ladder unconnected", 1, true) then reported = true end
	end
	T.eq (reported, true, "the skipped ladder is reported")
end)

-- A map's ladder with no dismount beside it (any plain CS map): thin across
-- y, 24 wide across x, standing at y 0.
local function PlainLadder (id)
	return BspEntity ("info_ladder",
		{
			["mins.x"] = "-12",
			["mins.y"] = "-1",
			["mins.z"] = "0",
			["maxs.x"] = "12",
			["maxs.y"] = "1",
			["maxs.z"] = "128",
			hammerid = id
		}
	)
end

local function GeneratedLadders (t)
	t.entities = SPAWNS
	local s = load (t)
	s.commands.mp_nav_generate (nil)
	s.Poll ()
	s.nav.generating, s.nav.areas = false, 20
	s.Poll ()
	return s
end

T.test ("a ladder with no dismount faces away from the wall beside it", function ()
	local s = GeneratedLadders (
		{
			mapEntities = { PlainLadder ("plain") },
			ladderAreas = { LadderArea (0), LadderArea (128) },
			wall = function (point) return point.y > 0 end
		}
	)
	T.eq (s.ladders [1].direction.y, -1, "the wall on +y, it faces -y")
	T.eq (s.ladders [1].direction.x, 0)
	T.eq (s.ladders [1].removed, nil)
end)

T.test ("a ladder with a wall on neither side or both says no facing and is skipped", function ()
	for _, wall in ipairs ({ function () return false end, function () return true end }) do
		local s = GeneratedLadders (
			{
				mapEntities = { PlainLadder ("plain") },
				ladderAreas = { LadderArea (0), LadderArea (128) },
				wall = wall
			}
		)
		T.eq (#s.ladders, 0)
		local reported = false
		for _, message in ipairs (s.printed) do
			if message:find ("no cardinal facing", 1, true) then reported = true end
		end
		T.eq (reported, true)
	end
end)

T.test ("what the engine connects a ladder to stands; only an end it left is filled", function ()
	local nook, foot, top = LadderArea (0), LadderArea (0), LadderArea (128)
	local s = GeneratedLadders (
		{
			mapEntities = { PlainLadder ("plain") },
			-- the nook lies nearest the ladder's foot
			ladderAreas = { nook, top },
			wall = function (point) return point.y > 0 end,
			engineConnects = function (ladder) ladder.bottomArea = foot end
		}
	)
	T.eq (s.ladders [1].bottomArea, foot, "the engine's foot kept, not the nearest area")
	T.eq (nook.ladders [s.ladders [1]], nil)
	T.eq (s.ladders [1].topArea, top, "the top it left is filled")
	T.eq (top.ladders [s.ladders [1]], true, "and connected back, for the way down")
	T.eq (s.ladders [1].removed, nil)
end)

T.test ("a ladder the engine connected at both ends needs nothing more", function ()
	local foot, head, nearer = LadderArea (0), LadderArea (128), LadderArea (128)
	local s = GeneratedLadders (
		{
			mapEntities = { PlainLadder ("plain") },
			ladderAreas = { nearer },
			wall = function (point) return point.y > 0 end,
			engineConnects = function (ladder) ladder.bottomArea, ladder.topArea = foot, head end
		}
	)
	T.eq (s.ladders [1].topArea, head)
	T.eq (nearer.ladders [s.ladders [1]], nil)
end)

T.test ("a hanging ladder's foot, which the engine puts on the floor above, moves to the floor beneath", function ()
	local floor, upper = LadderArea (-200), LadderArea (128)
	local s = GeneratedLadders (
		{
			mapEntities = { PlainLadder ("hanging") },
			-- the upper floor nearer the foot (at 0) than the floor beneath
			ladderAreas = { floor, upper },
			floorZ = -200,
			wall = function (point) return point.y > 0 and point.z > 0 end,
			engineConnects = function (ladder)
				ladder.bottomArea = upper
				upper.ladders [ladder] = true
			end
		}
	)
	local ladder = s.ladders [1]
	T.eq (ladder.removed, nil, "it is kept")
	T.eq (ladder.bottomArea, floor, "its foot on the floor beneath")
	T.eq (floor.ladders [ladder], true, "which climbs it")
	T.eq (ladder.topArea, upper, "its top on the upper floor")
	T.eq (upper.ladders [ladder], true, "which climbs down it")
end)

T.test ("a hanging ladder with no floor beneath it is skipped", function ()
	local upper = LadderArea (128)
	local s = GeneratedLadders (
		{
			mapEntities = { PlainLadder ("hanging") },
			ladderAreas = { upper },
			wall = function (point) return point.y > 0 and point.z > 0 end,
			engineConnects = function (ladder) ladder.bottomArea = upper end
		}
	)
	T.eq (s.ladders [1].removed, true)
end)

-- A mesh area holding ladders, as the engine lists them.
local function MeshArea (ladders)
	return { GetLadders = function () return ladders end }
end

T.test ("mp_nav_ladders builds the ladders again over the mesh, with no generation and no reset", function ()
	local old = { removedAt = nil }
	function old:Remove () self.removed = true end
	local s = load (
		{
			entities = SPAWNS,
			areas = 20,
			mapEntities = { PlainLadder ("plain") },
			ladderAreas = { LadderArea (0), LadderArea (128) },
			navAreas = { MeshArea ({ old }), MeshArea ({ old }) },
			wall = function (point) return point.y > 0 end
		}
	)
	s.commands.mp_nav_ladders (nil)
	T.eq (old.removed, true, "the old ladder goes")
	T.eq (#s.ladders, 0, "a ladder removed does not go at once, so its areas still hold it now")
	T.eq (s.delays.ws_nav_ladders > 0, true, "a timer of 0 runs before the removal, and would save the old beside the new")
	s.timers.ws_nav_ladders ()
	T.eq (#s.ladders, 1)
	T.eq (s.ladders [1].removed, nil)
	T.eq (table.concat (s.lifecycle, ","), "ladder,save", "saved; the map is not reset")
	T.eq (s.nav.began, 0, "no generation")
	T.eq (s.cleaned, 0)
end)

T.test ("mp_nav_ladders refuses a player who is not an admin, and a mesh being generated", function ()
	local s = load ({ entities = SPAWNS, areas = 20, mapEntities = { PlainLadder ("plain") } })
	local ply = Player (false)
	s.commands.mp_nav_ladders (ply)
	T.eq (s.timers.ws_nav_ladders, nil)
	T.eq (ply.said [1] ~= nil, true, "told why")
	s.commands.mp_nav_generate (nil)
	local admin = Player (true)
	s.commands.mp_nav_ladders (admin)
	T.eq (s.timers.ws_nav_ladders, nil)
	T.eq (admin.said [1]:find ("under way") ~= nil, true, admin.said [1] or "")
end)

T.test ("the server console may run it too", function ()
	local s = load ({ entities = SPAWNS })
	s.commands.mp_nav_generate (nil)
	s.Poll ()
	T.eq (s.nav.began, 1)
end)

T.test ("a player who is not an admin is refused", function ()
	local s = load ({ entities = SPAWNS })
	local ply = Player (false)
	s.commands.mp_nav_generate (ply)
	s.Poll ()
	T.eq (s.nav.began, 0)
	T.eq (#s.seeds, 0)
	T.eq (ply.said [1] ~= nil, true, "told why")
end)

T.test ("it is refused while one is under way", function ()
	local s = load ({ entities = SPAWNS })
	s.commands.mp_nav_generate (nil)
	local admin = Player (true)
	s.commands.mp_nav_generate (admin)
	T.eq (admin.said [1]:find ("already") ~= nil, true, "while the doors open: " .. admin.said [1])
	s.Poll ()
	local later = Player (true)
	s.commands.mp_nav_generate (later)
	T.eq (s.nav.began, 1, "only once")
	T.eq (later.said [1]:find ("already") ~= nil, true, "while it generates: " .. later.said [1])
end)

T.test ("every door, gate and bridge is unlocked and opened, and generation waits until none moves", function ()
	local slow, quick, prop = Door ("func_door", 3), Door ("func_door_rotating", 0), PropDoor ()
	local barrier = Barrier ()
	local entities = { slow, quick, prop, barrier }
	for _, e in ipairs (SPAWNS) do entities [#entities + 1] = e end
	local s = load ({ entities = entities })
	s.commands.mp_nav_generate (nil)
	for _, d in ipairs ({ slow, quick, prop }) do
		T.eq (d.inputs [1], "Unlock", d.class .. " unlocked")
		T.eq (d.inputs [2], "Open", d.class .. " opened")
	end
	T.eq (barrier.solid, false, "spawn barriers passable")
	s.Poll ()
	s.Poll ()
	T.eq (s.nav.began, 0, "not while a bridge still slides out")
	s.Poll ()
	T.eq (s.nav.began, 1, "once every door is open")
end)

T.test ("a bridge (a door that is a floor, flat and wide) is closed, laid in place, not opened", function ()
	local bridge = Door ("func_door", 2, { x = 82, y = 426, z = 10 })
	local rail = Door ("func_door_rotating", 0, { x = 6, y = 410, z = 6 })
	local entities = { bridge, rail }
	for _, e in ipairs (SPAWNS) do entities [#entities + 1] = e end
	local s = load ({ entities = entities })
	s.commands.mp_nav_generate (nil)
	T.eq (bridge.inputs [2], "Close", "the bridge laid out")
	T.eq (rail.inputs [2], "Open", "a handrail is no floor: opened like a door")
	s.Poll ()
	T.eq (s.nav.began, 0, "not while the bridge slides out")
	s.Poll ()
	T.eq (s.nav.began, 1, "once it is in place")
end)

T.test ("the generator walks through doors, so a laid bridge gets a solid stand-in to walk on", function ()
	local bridge = Door ("func_door", 0, { x = 82, y = 426, z = 10 })
	local door = Door ("func_door", 0)
	local entities = { bridge, door }
	for _, e in ipairs (SPAWNS) do entities [#entities + 1] = e end
	local s = load ({ entities = entities })
	s.commands.mp_nav_generate (nil)
	T.eq (#s.created, 0, "none before the bridge is in place")
	s.Poll ()
	T.eq (s.nav.began, 1, "generating")
	T.eq (#s.created, 1, "one, for the bridge alone")
	local standIn = s.created [1]
	T.eq (standIn.class, "func_brush", "a brush")
	T.eq (standIn.model, "*7", "the bridge's own brush")
	T.eq (standIn.pos.y, 20, "where the bridge lies")
	T.eq (standIn.angles.y, 90, "as it lies")
	T.eq (standIn.keys.Solidity, "2", "always solid, which the generator walks on")
	T.eq (standIn.spawned, true, "spawned")
end)

T.test ("a door that never settles holds generation back no more than DOOR_WAIT", function ()
	local stuck = Door ("func_door", 1e9)
	local entities = { stuck }
	for _, e in ipairs (SPAWNS) do entities [#entities + 1] = e end
	local s = load ({ entities = entities })
	s.commands.mp_nav_generate (nil)
	for _ = 1, 120 do s.Poll () if s.nav.began > 0 then break end end
	T.eq (s.nav.began, 1, "began anyway")
	T.eq (s.now <= 61, true, "within a minute: " .. s.now)
end)

T.test ("when it is done the map is reset and the admin told the areas it made", function ()
	local s = load ({ entities = SPAWNS })
	local admin = Player (true)
	s.commands.mp_nav_generate (admin)
	s.Poll ()
	local said = #admin.said
	s.Poll ()
	T.eq (s.cleaned, 0, "not while it generates")
	s.nav.generating, s.nav.areas = false, 2133
	s.Poll ()
	T.eq (s.cleaned, 1, "the map's doors and gates put back")
	T.eq (admin.said [said + 1]:find ("2133") ~= nil, true, admin.said [said + 1])
	T.eq (s.timers [GENERATE_POLL], nil, "and it stops watching")
end)

-- Sandbox mode: no rounds to close doors, no spawning while it generates.

T.test ("in Gameplay mode it enters Sandbox mode first", function ()
	local s = load ({ entities = SPAWNS, gameplay = true })
	s.commands.mp_nav_generate (Player (true))
	T.eq (s.requests [1], Gamemode.SANDBOX, "asked for Sandbox mode")
	s.Poll ()
	T.eq (s.nav.began, 1, "then generates")
end)

T.test ("in Sandbox mode it asks for nothing", function ()
	local s = load ({ entities = SPAWNS })
	s.commands.mp_nav_generate (nil)
	T.eq (#s.requests, 0)
end)

T.test ("with Sandbox mode disabled it is refused, and says how to allow it", function ()
	local s = load ({ entities = SPAWNS, gameplay = true, noSandbox = true })
	local admin = Player (true)
	s.commands.mp_nav_generate (admin)
	s.Poll ()
	T.eq (s.nav.began, 0)
	T.eq (#s.requests, 0)
	T.eq (admin.said [1]:find ("sv_gameplay_disable_sandbox", 1, true) ~= nil, true, admin.said [1])
end)

T.test ("every spawn limit is 0 while it generates, and put back after", function ()
	local s = load (
		{
			entities = SPAWNS,
			cleanups = { "props", "npcs", "duplicates" }, -- cleanup.GetTable(): a list of kinds
			limits = { sbox_maxprops = "150", sbox_maxnpcs = "10" }
		}
	)
	s.commands.mp_nav_generate (nil)
	T.eq (s.convars.sbox_maxprops, "0", "props")
	T.eq (s.convars.sbox_maxnpcs, "0", "npcs")
	T.eq (s.convars.sbox_maxduplicates, nil, "a kind with no limit is left alone")
	s.Poll ()
	s.nav.generating = false
	s.Poll ()
	T.eq (s.convars.sbox_maxprops, "150", "props put back")
	T.eq (s.convars.sbox_maxnpcs, "10", "npcs put back")
end)

T.test ("every client is told each stage: opening the doors, generating, done with the areas made", function ()
	local Progress = T.require ("includes.nav_progress")
	local s = load ({ entities = SPAWNS })
	s.commands.mp_nav_generate (nil)
	s.Poll ()
	s.nav.generating, s.nav.areas = false, 2426
	s.Poll ()
	T.eq (#s.stages, 3)
	T.eq (s.stages [1].stage, Progress.OPENING)
	T.eq (s.stages [2].stage, Progress.GENERATING)
	T.eq (s.stages [3].stage, Progress.DONE)
	T.eq (s.stages [3].areas, 2426)
	for _, told in ipairs (s.stages) do T.eq (told.extra, nil, "the progress alone: each client keeps its own time") end
end)

T.test ("spawning is locked from the start until it is done, then unlocked", function ()
	local s = load ({ entities = SPAWNS })
	T.eq (#s.locks, 0, "before")
	s.commands.mp_nav_generate (nil)
	T.eq (table.concat (s.locks, ","), "lock nav", "while the doors open")
	s.Poll ()
	T.eq (#s.locks, 1, "still, while it generates")
	s.nav.generating, s.nav.areas = false, 2426
	s.Poll ()
	T.eq (table.concat (s.locks, ","), "lock nav,unlock nav", "unlocked when done")
end)

T.test ("a mesh is usable once it has areas", function ()
	T.eq (load ({ areas = 0 }).ws.NavMeshUsable (), false)
	T.eq (load ({ areas = 12 }).ws.NavMeshUsable (), true)
end)

-- Seams (nextsoldier.world.nav_gaps) -------------------------------------------------------

-- A flat nav area over x0..x1, y0..y1 at height z.
local function NavArea (id, x0, y0, x1, y1, z)
	local a = { id = id, links = {} }
	function a:GetID () return self.id end
	function a:GetExtentInfo () return { lo = V (x0, y0, z or 0), hi = V (x1, y1, z or 0) } end
	function a:GetZ () return z or 0 end
	function a:GetHidingSpots () return {} end
	function a:IsConnected (other) return self.links [other] == true end
	function a:ConnectTo (other) self.links [other] = true end
	return a
end

-- Runs the seam sweep's timer until it is done.
local function Sweep (s)
	while s.timers.ws_nav_gaps do s.timers.ws_nav_gaps () end
end

local function TwoAcrossASeam ()
	return NavArea (1, 0, 0, 100, 100), NavArea (2, 125, 0, 225, 100)
end

-- A flight: a slanted player clip rising toward lower y, z = 1000 - y.
local function ClippedStair ()
	local function Side (x, y, z, dist) return { plane = { normal = V (x, y, z), dist = dist }, bevel = 0 } end
	local ROOT2 = math.sqrt (2) / 2
	return
	{
		contents = nextsoldier.world.nav_stairs.PLAYER_CLIP,
		sides =
		{
			Side (1, 0, 0, 100), Side (-1, 0, 0, 0), Side (0, 1, 0, 1000), Side (0, -1, 0, -800),
			Side (0, 0, 1, 200), Side (0, 0, -1, 0), Side (0, ROOT2, ROOT2, 1000 * ROOT2)
		}
	}
end

local function StairArea (id, y0, y1, zLowY, zHighY, s)
	local a = NavArea (id, 0, y0, 100, y1, zLowY)
	function a:GetExtentInfo () return { lo = V (0, y0, zLowY), hi = V (100, y1, zHighY) } end
	function a:GetCorner (corner) return { z = (corner == 0 or corner == 1) and zLowY or zHighY } end
	function a:GetAdjacentAreas () return {} end
	function a:Remove () s.lifecycle [#s.lifecycle + 1] = "remove " .. id end
	return a
end

T.test ("a broken flight is laid as a ramp, saved once its fragments are gone, then its seams linked", function ()
	local log = {}
	local areas =
	{
		StairArea (1, 990, 1020, 0, 0, { lifecycle = log }),
		StairArea (2, 900, 925, 100, 75, { lifecycle = log }),
		StairArea (3, 780, 820, 200, 200, { lifecycle = log })
	}
	local s = load ({ areas = 3, navAreas = {}, brushes = { ClippedStair () }, stairAreas = areas })
	s.hooks.InitPostEntity ()
	s.timers.ws_nav_gaps ()
	T.eq (table.concat (s.lifecycle, ","), "ramp", "not saved in the tick an area is removed, which lingers until the next")
	T.eq (table.concat (log, ","), "remove 2", "the fragment")
	T.eq (s.ramps [1].attributes, 4096, "marked as stairs")
	T.eq (s.ramps [1].links [areas [1]] and s.ramps [1].links [areas [3]], true, "joined to the floor and the landing")
	T.eq (areas [1].links [s.ramps [1]] and areas [3].links [s.ramps [1]], true, "both ways")
	T.eq (s.timers.ws_nav_gaps, nil, "the seams wait for the save")
	s.nextTick ()
	T.eq (table.concat (s.lifecycle, ","), "ramp,save")
	T.eq (s.timers.ws_nav_gaps ~= nil, true, "then the seams")
end)

T.test ("a flight's floors are looked for past the clip's ends, where the mesh's areas stop short", function ()
	local s = load ({ areas = 2, navAreas = {}, brushes = { ClippedStair () }, stairAreas = {} })
	s.hooks.InitPostEntity ()
	s.timers.ws_nav_gaps ()
	T.eq (s.stairBox.mins.y < 800, true, "beyond the top")
	T.eq (s.stairBox.maxs.y > 1000, true, "and beyond the foot")
	T.eq (s.stairBox.mins.x < 0 and s.stairBox.maxs.x > 100, true, "and to either side")
end)

T.test ("a map with no broken flight is not saved", function ()
	local s = load ({ areas = 2, navAreas = {}, brushes = { ClippedStair () }, stairAreas = {} })
	s.hooks.InitPostEntity ()
	s.timers.ws_nav_gaps ()
	T.eq (table.concat (s.lifecycle, ","), "", "nothing laid, nothing saved")
	T.eq (s.nextTick, nil)
	T.eq (s.timers.ws_nav_gaps ~= nil, true, "the seams go on at once")
end)

T.test ("once the map has loaded, a seam a walker crosses is linked both ways", function ()
	local a, b = TwoAcrossASeam ()
	local s = load ({ areas = 2, navAreas = { a, b } })
	s.hooks.InitPostEntity ()
	Sweep (s)
	T.eq (a:IsConnected (b), true, "one way")
	T.eq (b:IsConnected (a), true, "and back")
	T.eq (table.concat (s.ran, ","), "WSNavLinked", "routes planned before are told the mesh changed")
end)

T.test ("the mesh loads after the map's entities: the sweep waits for it", function ()
	local a, b = TwoAcrossASeam ()
	local s = load ({ areas = 0, navAreas = { a, b } })
	s.hooks.InitPostEntity ()
	s.timers.ws_nav_gaps ()
	T.eq (a:IsConnected (b), false, "no mesh yet")
	s.nav.areas = 2
	Sweep (s)
	T.eq (a:IsConnected (b) and b:IsConnected (a), true, "linked once it loaded")
end)

T.test ("a seam the walker cannot cross, or with no floor under it, stays open", function ()
	local a, b = TwoAcrossASeam ()
	-- a wall: every sweep hits
	local s = load ({ areas = 2, navAreas = { a, b }, trace = function () return { Hit = true } end })
	s.hooks.InitPostEntity ()
	Sweep (s)
	T.eq (a:IsConnected (b) or b:IsConnected (a), false, "a wall")
	T.eq (#s.ran, 0, "nothing linked, nothing changed")
	-- a drop: nothing is ever hit, not even a floor
	a, b = TwoAcrossASeam ()
	s = load ({ areas = 2, navAreas = { a, b }, trace = function () return { Hit = false } end })
	s.hooks.InitPostEntity ()
	Sweep (s)
	T.eq (a:IsConnected (b) or b:IsConnected (a), false, "no floor")
end)

T.test ("on a players' map the walker is swept under the player's clips, else the NPC's", function ()
	local a, b = TwoAcrossASeam ()
	local s = load ({ areas = 2, navAreas = { a, b }, entities = { Ent ("tf_gamerules", 0, 0, 0) } })
	s.hooks.InitPostEntity ()
	Sweep (s)
	T.eq (s.sweeps [1].mask, 2, "MASK_PLAYERSOLID_BRUSHONLY")
	a, b = TwoAcrossASeam ()
	s = load ({ areas = 2, navAreas = { a, b }, entities = { Ent ("info_player_start", 0, 0, 0) } })
	s.hooks.InitPostEntity ()
	Sweep (s)
	T.eq (s.sweeps [1].mask, 4, "MASK_NPCSOLID_BRUSHONLY")
end)

T.test ("a mesh just generated has its seams linked too", function ()
	local a, b = TwoAcrossASeam ()
	local s = load ({ entities = SPAWNS, navAreas = { a, b } })
	s.commands.mp_nav_generate (Player (true))
	s.Poll ()
	s.nav.generating, s.nav.areas = false, 2
	s.Poll ()
	Sweep (s)
	T.eq (a:IsConnected (b) and b:IsConnected (a), true, "linked")
end)

-- An idle server builds its own mesh: once it is idle (WSServerIdle,
-- sv_idle.lua), with no mesh, it runs mp_nav_generate as the console
-- would, and goes back to Gameplay mode after when it left it to generate.
local function Idle (s)
	s.hooks.WSServerIdle ()
end

T.test ("an idle server with no mesh generates one", function ()
	local s = load ({ entities = SPAWNS })
	T.eq (#s.seeds, 0, "nothing before it is idle")
	Idle (s)
	T.eq (#s.seeds, 4, "seeded once idle")
	s.Poll ()
	T.eq (s.nav.began, 1, "and generating")
end)

T.test ("a map with a mesh is left alone", function ()
	local s = load ({ entities = SPAWNS, areas = 12 })
	Idle (s)
	T.eq (#s.seeds, 0, "not generated")
end)

T.test ("an admin's run already under way is not doubled", function ()
	local s = load ({ entities = SPAWNS })
	s.commands.mp_nav_generate (Player (true))
	Idle (s)
	T.eq (#s.seeds, 4, "seeded once")
end)

T.test ("leaving Gameplay mode to generate, it goes back after", function ()
	local s = load ({ entities = SPAWNS, gameplay = true })
	Idle (s)
	T.eq (s.requests [1], Gamemode.SANDBOX, "into Sandbox mode")
	s.Poll ()
	s.nav.generating, s.nav.areas = false, 2133
	s.Poll ()
	T.eq (s.requests [2], Gamemode.GAMEPLAY, "back to Gameplay mode")
	local sandbox = load ({ entities = SPAWNS })
	Idle (sandbox)
	sandbox.Poll ()
	sandbox.nav.generating, sandbox.nav.areas = false, 2133
	sandbox.Poll ()
	T.eq (#sandbox.requests, 0, "in Sandbox mode already: stays there")
end)

T.test ("with Sandbox mode disabled an idle server does not generate", function ()
	local s = load ({ entities = SPAWNS, gameplay = true, noSandbox = true })
	Idle (s)
	s.Poll ()
	T.eq (s.nav.began, 0, "not generated")
	T.eq (#s.requests, 0, "the game left running")
end)

T.finish ()
