-- mp_nav_generate (ws/sv_nav.lua): an admin, or the server console,
-- builds the map's navigation mesh. GMod's generator walks out from seeds,
-- and TF2 maps spawn players at info_player_teamspawn, which it does not
-- seed from: every spawn point and control point is a seed. It walks only
-- what stands in place, so every door, gate and bridge is opened first,
-- spawn barriers made passable, and the map reset when it is done. Run
-- against fakes of concommand, ents, navmesh, timer and game.
local T = dofile("tests/harness.lua")
local Gamemode = T.require("games.system.gamemode")

local function Ent(class, x, y, z)
	return { class = class, GetClass = function() return class end, GetPos = function() return { x = x, y = y, z = z } end }
end

local function Player(admin)
	local p = { said = {} }
	function p:IsAdmin() return admin end
	function p:ChatPrint(text) self.said[#self.said + 1] = text end
	return p
end

-- A func_door (m_toggle_state: 0 open, 1 closed, 2 opening, 3 closing) that
-- takes `travel` polls to move once told to; `size` its brush (default a
-- door's: 64 wide, 8 deep, 128 tall).
local function Door(class, travel, size)
	local d = Ent(class, 0, 0, 0)
	d.state, d.inputs, d.travel = 1, {}, travel or 0
	size = size or { x = 64, y = 8, z = 128 }
	function d:GetModel() return "*7" end
	function d:GetPos() return { x = 10, y = 20, z = 30 } end
	function d:GetAngles() return { p = 0, y = 90, r = 0 } end
	function d:OBBMins() return { x = -size.x / 2, y = -size.y / 2, z = 0 } end
	function d:OBBMaxs() return { x = size.x / 2, y = size.y / 2, z = size.z } end
	function d:Fire(input)
		self.inputs[#self.inputs + 1] = input
		if input == "Open" then self.state = self.travel > 0 and 2 or 0 end
		if input == "Close" then self.state = self.travel > 0 and 3 or 1 end
	end
	function d:GetInternalVariable(name) return name == "m_toggle_state" and self.state or nil end
	function d:Tick()
		if self.state < 2 then return end
		self.travel = self.travel - 1
		if self.travel <= 0 then self.state = self.state == 2 and 0 or 1 end
	end
	return d
end

-- A prop_door_rotating (m_eDoorState: 0 closed, 1 opening, 2 open, 3 closing).
local function PropDoor()
	local d = Ent("prop_door_rotating", 0, 0, 0)
	d.state, d.inputs = 0, {}
	function d:OBBMins() return { x = -27, y = -2, z = 0 } end
	function d:OBBMaxs() return { x = 27, y = 2, z = 108 } end
	function d:Fire(input) self.inputs[#self.inputs + 1] = input if input == "Open" then self.state = 2 end end
	function d:GetInternalVariable(name) return name == "m_eDoorState" and self.state or nil end
	function d:Tick() end
	return d
end

local function Barrier()
	local b = Ent("func_respawnroomvisualizer", 0, 0, 0)
	b.solid = true
	function b:SetNotSolid(off) self.solid = not off end
	return b
end

-- A vector with the arithmetic the seam sweep does.
local Vec = {}
Vec.__index = Vec
local function V(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vec) end
Vec.__add = function(a, b) return V(a.x + b.x, a.y + b.y, a.z + b.z) end
Vec.__sub = function(a, b) return V(a.x - b.x, a.y - b.y, a.z - b.z) end
Vec.__div = function(a, n) return V(a.x / n, a.y / n, a.z / n) end

local GENERATE_POLL = "ws_nav_generate"

local function load(t)
	local s = { commands = {}, seeds = {}, timers = {}, delays = {}, cleaned = 0, now = 0, hooks = {}, sweeps = {}, ran = {} }
	s.humans = t.humans or {}
	-- the mesh's areas (NavArea fakes) and what a sweep across a seam hits:
	-- trace(t) -> { Hit, StartSolid }
	s.navAreas = t.navAreas or {}
	s.trace = t.trace or function(tr) return { Hit = tr.endpos.z < tr.start.z, StartSolid = false } end
	s.nav = { generating = false, areas = t.areas or 0, began = 0 }
	s.convars = {
		sv_gameplay_enabled = t.gameplay and "1" or "0",
		sv_gameplay_disable_sandbox = t.noSandbox and "1" or "0",
	}
	for name, value in pairs(t.limits or {}) do s.convars[name] = value end
	s.requests, s.sent, s.created = {}, {}, {}
	s.stages = {}
	s.locks = {}
	s.ws = {
		require = T.require,
		LockSpawns = function(lock) s.locks[#s.locks + 1] = "lock " .. lock end,
		UnlockSpawns = function(lock) s.locks[#s.locks + 1] = "unlock " .. lock end,
		-- The server console (nil) may; a player as their admin flag says.
		Can = function(ply) return ply == nil or ply:IsAdmin() end,
		NavProgress = function(stage, areas, extra)
			s.stages[#s.stages + 1] = { stage = stage, areas = areas, extra = extra }
		end,
		Feature = function(name)
			assert(name == "gamemode", name)
			return {
				Request = function(_, want, source, requester)
					s.requests[#s.requests + 1] = want
					s.convars.sv_gameplay_enabled = want == Gamemode.GAMEPLAY and "1" or "0"
					return true
				end,
			}
		end,
	}
	local env = setmetatable({
		GetConVar = function(name)
			if s.convars[name] == nil then return nil end
			return {
				GetBool = function() return s.convars[name] ~= "0" end,
				GetString = function() return s.convars[name] end,
				SetString = function(_, v) s.convars[name] = v end,
			}
		end,
		cleanup = { GetTable = function() return t.cleanups or {} end },
		WS = s.ws,
		concommand = { Add = function(name, fn) s.commands[name] = fn end },
		ents = {
			Create = function(class)
				local e = { class = class, keys = {}, spawned = false }
				function e:SetModel(m) self.model = m end
				function e:SetPos(p) self.pos = p end
				function e:SetAngles(a) self.angles = a end
				function e:SetKeyValue(k, v) self.keys[k] = v end
				function e:Spawn() self.spawned = true end
				s.created[#s.created + 1] = e
				return e
			end,
			GetAll = function() return t.entities or {} end,
			FindByClass = function(class)
				local found = {}
				for _, e in ipairs(t.entities or {}) do if e.class == class then found[#found + 1] = e end end
				return found
			end,
		},
		navmesh = {
			AddWalkableSeed = function(pos, normal) s.seeds[#s.seeds + 1] = { pos = pos, normal = normal } end,
			BeginGeneration = function() s.nav.began = s.nav.began + 1 s.nav.generating = true end,
			IsGenerating = function() return s.nav.generating end,
			IsLoaded = function() return s.nav.areas > 0 end,
			GetNavAreaCount = function() return s.nav.areas end,
			GetAllNavAreas = function() return s.navAreas end,
		},
		hook = {
			Add = function(event, name, fn)
				local before = s.hooks[event]
				-- as GMod's: the first hook to answer decides
				s.hooks[event] = function(...)
					local answer = before and before(...)
					if answer ~= nil then return answer end
					return fn(...)
				end
			end,
			Run = function(event) s.ran[#s.ran + 1] = event end,
		},
		util = { TraceHull = function(tr) s.sweeps[#s.sweeps + 1] = tr return s.trace(tr) end },
		MASK_PLAYERSOLID = 1, MASK_PLAYERSOLID_BRUSHONLY = 2, MASK_NPCSOLID = 3, MASK_NPCSOLID_BRUSHONLY = 4,
		timer = {
			Create = function(name, delay, reps, fn)
				s.timers[name], s.delays[name] = fn, delay
			end,
			Remove = function(name) s.timers[name] = nil end,
		},
		player = { GetHumans = function() return s.humans end },
		game = { GetMap = function() return "cp_steel" end, CleanUpMap = function() s.cleaned = s.cleaned + 1 end },
		CurTime = function() return s.now end,
		Vector = V,
		IsValid = function(p) return p ~= nil end,
		print = function() end,
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sv_nav.lua")), env)()
	-- one poll of its timer, a second on, the doors moving meanwhile
	function s.Poll()
		s.now = s.now + 1
		for _, e in ipairs(t.entities or {}) do if e.Tick then e:Tick() end end
		local poll = s.timers[GENERATE_POLL]
		if poll then poll() end
	end
	return s
end

local SPAWNS = {
	Ent("info_player_teamspawn", 1, 2, 3),
	Ent("info_player_teamspawn", 4, 5, 6),
	Ent("info_player_start", 7, 8, 9),
	Ent("team_control_point", 10, 11, 12),
	Ent("prop_physics", 0, 0, 0),
}

T.test("an admin's mp_nav_generate seeds every spawn and control point, facing up, and begins", function()
	local s = load({ entities = SPAWNS })
	local admin = Player(true)
	s.commands.mp_nav_generate(admin)
	s.Poll()
	T.eq(#s.seeds, 4, "three spawns and a point")
	for _, seed in ipairs(s.seeds) do T.eq(seed.normal.z, 1, "facing up") end
	T.eq(s.nav.began, 1, "generation began")
	T.eq(#admin.said >= 1, true, "told it began")
end)

T.test("the server console may run it too", function()
	local s = load({ entities = SPAWNS })
	s.commands.mp_nav_generate(nil)
	s.Poll()
	T.eq(s.nav.began, 1)
end)

T.test("a player who is not an admin is refused", function()
	local s = load({ entities = SPAWNS })
	local ply = Player(false)
	s.commands.mp_nav_generate(ply)
	s.Poll()
	T.eq(s.nav.began, 0)
	T.eq(#s.seeds, 0)
	T.eq(ply.said[1] ~= nil, true, "told why")
end)

T.test("it is refused while one is under way", function()
	local s = load({ entities = SPAWNS })
	s.commands.mp_nav_generate(nil)
	local admin = Player(true)
	s.commands.mp_nav_generate(admin)
	T.eq(admin.said[1]:find("already") ~= nil, true, "while the doors open: " .. admin.said[1])
	s.Poll()
	local later = Player(true)
	s.commands.mp_nav_generate(later)
	T.eq(s.nav.began, 1, "only once")
	T.eq(later.said[1]:find("already") ~= nil, true, "while it generates: " .. later.said[1])
end)

T.test("every door, gate and bridge is unlocked and opened, and generation waits until none moves", function()
	local slow, quick, prop = Door("func_door", 3), Door("func_door_rotating", 0), PropDoor()
	local barrier = Barrier()
	local entities = { slow, quick, prop, barrier }
	for _, e in ipairs(SPAWNS) do entities[#entities + 1] = e end
	local s = load({ entities = entities })
	s.commands.mp_nav_generate(nil)
	for _, d in ipairs({ slow, quick, prop }) do
		T.eq(d.inputs[1], "Unlock", d.class .. " unlocked")
		T.eq(d.inputs[2], "Open", d.class .. " opened")
	end
	T.eq(barrier.solid, false, "spawn barriers passable")
	s.Poll()
	s.Poll()
	T.eq(s.nav.began, 0, "not while a bridge still slides out")
	s.Poll()
	T.eq(s.nav.began, 1, "once every door is open")
end)

T.test("a bridge (a door that is a floor, flat and wide) is closed, laid in place, not opened", function()
	local bridge = Door("func_door", 2, { x = 82, y = 426, z = 10 })
	local rail = Door("func_door_rotating", 0, { x = 6, y = 410, z = 6 })
	local entities = { bridge, rail }
	for _, e in ipairs(SPAWNS) do entities[#entities + 1] = e end
	local s = load({ entities = entities })
	s.commands.mp_nav_generate(nil)
	T.eq(bridge.inputs[2], "Close", "the bridge laid out")
	T.eq(rail.inputs[2], "Open", "a handrail is no floor: opened like a door")
	s.Poll()
	T.eq(s.nav.began, 0, "not while the bridge slides out")
	s.Poll()
	T.eq(s.nav.began, 1, "once it is in place")
end)

T.test("the generator walks through doors, so a laid bridge gets a solid stand-in to walk on", function()
	local bridge = Door("func_door", 0, { x = 82, y = 426, z = 10 })
	local door = Door("func_door", 0)
	local entities = { bridge, door }
	for _, e in ipairs(SPAWNS) do entities[#entities + 1] = e end
	local s = load({ entities = entities })
	s.commands.mp_nav_generate(nil)
	T.eq(#s.created, 0, "none before the bridge is in place")
	s.Poll()
	T.eq(s.nav.began, 1, "generating")
	T.eq(#s.created, 1, "one, for the bridge alone")
	local standIn = s.created[1]
	T.eq(standIn.class, "func_brush", "a brush")
	T.eq(standIn.model, "*7", "the bridge's own brush")
	T.eq(standIn.pos.y, 20, "where the bridge lies")
	T.eq(standIn.angles.y, 90, "as it lies")
	T.eq(standIn.keys.Solidity, "2", "always solid, which the generator walks on")
	T.eq(standIn.spawned, true, "spawned")
end)

T.test("a door that never settles holds generation back no more than DOOR_WAIT", function()
	local stuck = Door("func_door", 1e9)
	local entities = { stuck }
	for _, e in ipairs(SPAWNS) do entities[#entities + 1] = e end
	local s = load({ entities = entities })
	s.commands.mp_nav_generate(nil)
	for _ = 1, 120 do s.Poll() if s.nav.began > 0 then break end end
	T.eq(s.nav.began, 1, "began anyway")
	T.eq(s.now <= 61, true, "within a minute: " .. s.now)
end)

T.test("when it is done the map is reset and the admin told the areas it made", function()
	local s = load({ entities = SPAWNS })
	local admin = Player(true)
	s.commands.mp_nav_generate(admin)
	s.Poll()
	local said = #admin.said
	s.Poll()
	T.eq(s.cleaned, 0, "not while it generates")
	s.nav.generating, s.nav.areas = false, 2133
	s.Poll()
	T.eq(s.cleaned, 1, "the map's doors and gates put back")
	T.eq(admin.said[said + 1]:find("2133") ~= nil, true, admin.said[said + 1])
	T.eq(s.timers[GENERATE_POLL], nil, "and it stops watching")
end)

-- Sandbox mode: no rounds to close doors, no spawning while it generates.

T.test("in Gameplay mode it enters Sandbox mode first", function()
	local s = load({ entities = SPAWNS, gameplay = true })
	s.commands.mp_nav_generate(Player(true))
	T.eq(s.requests[1], Gamemode.SANDBOX, "asked for Sandbox mode")
	s.Poll()
	T.eq(s.nav.began, 1, "then generates")
end)

T.test("in Sandbox mode it asks for nothing", function()
	local s = load({ entities = SPAWNS })
	s.commands.mp_nav_generate(nil)
	T.eq(#s.requests, 0)
end)

T.test("with Sandbox mode disabled it is refused, and says how to allow it", function()
	local s = load({ entities = SPAWNS, gameplay = true, noSandbox = true })
	local admin = Player(true)
	s.commands.mp_nav_generate(admin)
	s.Poll()
	T.eq(s.nav.began, 0)
	T.eq(#s.requests, 0)
	T.eq(admin.said[1]:find("sv_gameplay_disable_sandbox", 1, true) ~= nil, true, admin.said[1])
end)

T.test("every spawn limit is 0 while it generates, and put back after", function()
	local s = load({
		entities = SPAWNS,
		cleanups = { "props", "npcs", "duplicates" }, -- cleanup.GetTable(): a list of kinds
		limits = { sbox_maxprops = "150", sbox_maxnpcs = "10" },
	})
	s.commands.mp_nav_generate(nil)
	T.eq(s.convars.sbox_maxprops, "0", "props")
	T.eq(s.convars.sbox_maxnpcs, "0", "npcs")
	T.eq(s.convars.sbox_maxduplicates, nil, "a kind with no limit is left alone")
	s.Poll()
	s.nav.generating = false
	s.Poll()
	T.eq(s.convars.sbox_maxprops, "150", "props put back")
	T.eq(s.convars.sbox_maxnpcs, "10", "npcs put back")
end)

T.test("every client is told each stage: opening the doors, generating, done with the areas made", function()
	local Progress = T.require("ws.nav_progress")
	local s = load({ entities = SPAWNS })
	s.commands.mp_nav_generate(nil)
	s.Poll()
	s.nav.generating, s.nav.areas = false, 2426
	s.Poll()
	T.eq(#s.stages, 3)
	T.eq(s.stages[1].stage, Progress.OPENING)
	T.eq(s.stages[2].stage, Progress.GENERATING)
	T.eq(s.stages[3].stage, Progress.DONE)
	T.eq(s.stages[3].areas, 2426)
	for _, told in ipairs(s.stages) do T.eq(told.extra, nil, "the progress alone: each client keeps its own time") end
end)


T.test("spawning is locked from the start until it is done, then unlocked", function()
	local s = load({ entities = SPAWNS })
	T.eq(#s.locks, 0, "before")
	s.commands.mp_nav_generate(nil)
	T.eq(table.concat(s.locks, ","), "lock nav", "while the doors open")
	s.Poll()
	T.eq(#s.locks, 1, "still, while it generates")
	s.nav.generating, s.nav.areas = false, 2426
	s.Poll()
	T.eq(table.concat(s.locks, ","), "lock nav,unlock nav", "unlocked when done")
end)

T.test("a mesh is usable once it has areas", function()
	T.eq(load({ areas = 0 }).ws.NavMeshUsable(), false)
	T.eq(load({ areas = 12 }).ws.NavMeshUsable(), true)
end)

-- Seams (games.ns.nav_gaps) -------------------------------------------------------

-- A flat nav area over x0..x1, y0..y1 at height z.
local function NavArea(id, x0, y0, x1, y1, z)
	local a = { id = id, links = {} }
	function a:GetID() return self.id end
	function a:GetExtentInfo() return { lo = V(x0, y0, z or 0), hi = V(x1, y1, z or 0) } end
	function a:GetZ() return z or 0 end
	function a:IsConnected(other) return self.links[other] == true end
	function a:ConnectTo(other) self.links[other] = true end
	return a
end

-- Runs the seam sweep's timer until it is done.
local function Sweep(s)
	while s.timers.ws_nav_gaps do s.timers.ws_nav_gaps() end
end

local function TwoAcrossASeam()
	return NavArea(1, 0, 0, 100, 100), NavArea(2, 125, 0, 225, 100)
end

T.test("once the map has loaded, a seam a walker crosses is linked both ways", function()
	local a, b = TwoAcrossASeam()
	local s = load({ areas = 2, navAreas = { a, b } })
	s.hooks.InitPostEntity()
	Sweep(s)
	T.eq(a:IsConnected(b), true, "one way")
	T.eq(b:IsConnected(a), true, "and back")
	T.eq(table.concat(s.ran, ","), "WSNavLinked", "routes planned before are told the mesh changed")
end)

T.test("the mesh loads after the map's entities: the sweep waits for it", function()
	local a, b = TwoAcrossASeam()
	local s = load({ areas = 0, navAreas = { a, b } })
	s.hooks.InitPostEntity()
	s.timers.ws_nav_gaps()
	T.eq(a:IsConnected(b), false, "no mesh yet")
	s.nav.areas = 2
	Sweep(s)
	T.eq(a:IsConnected(b) and b:IsConnected(a), true, "linked once it loaded")
end)

T.test("a seam the walker cannot cross, or with no floor under it, stays open", function()
	local a, b = TwoAcrossASeam()
	-- a wall: every sweep hits
	local s = load({ areas = 2, navAreas = { a, b }, trace = function() return { Hit = true } end })
	s.hooks.InitPostEntity()
	Sweep(s)
	T.eq(a:IsConnected(b) or b:IsConnected(a), false, "a wall")
	T.eq(#s.ran, 0, "nothing linked, nothing changed")
	-- a drop: nothing is ever hit, not even a floor
	a, b = TwoAcrossASeam()
	s = load({ areas = 2, navAreas = { a, b }, trace = function() return { Hit = false } end })
	s.hooks.InitPostEntity()
	Sweep(s)
	T.eq(a:IsConnected(b) or b:IsConnected(a), false, "no floor")
end)

T.test("on a players' map the walker is swept under the player's clips, else the NPC's", function()
	local a, b = TwoAcrossASeam()
	local s = load({ areas = 2, navAreas = { a, b }, entities = { Ent("tf_gamerules", 0, 0, 0) } })
	s.hooks.InitPostEntity()
	Sweep(s)
	T.eq(s.sweeps[1].mask, 2, "MASK_PLAYERSOLID_BRUSHONLY")
	a, b = TwoAcrossASeam()
	s = load({ areas = 2, navAreas = { a, b }, entities = { Ent("info_player_start", 0, 0, 0) } })
	s.hooks.InitPostEntity()
	Sweep(s)
	T.eq(s.sweeps[1].mask, 4, "MASK_NPCSOLID_BRUSHONLY")
end)

T.test("a mesh just generated has its seams linked too", function()
	local a, b = TwoAcrossASeam()
	local s = load({ entities = SPAWNS, navAreas = { a, b } })
	s.commands.mp_nav_generate(Player(true))
	s.Poll()
	s.nav.generating, s.nav.areas = false, 2
	s.Poll()
	Sweep(s)
	T.eq(a:IsConnected(b) and b:IsConnected(a), true, "linked")
end)

-- An idle server builds its own mesh: once it is idle (WSServerIdle,
-- ws/sv_idle.lua), with no mesh, it runs mp_nav_generate as the console
-- would, and goes back to Gameplay mode after when it left it to generate.
local function Idle(s)
	s.hooks.WSServerIdle()
end

T.test("an idle server with no mesh generates one", function()
	local s = load({ entities = SPAWNS })
	T.eq(#s.seeds, 0, "nothing before it is idle")
	Idle(s)
	T.eq(#s.seeds, 4, "seeded once idle")
	s.Poll()
	T.eq(s.nav.began, 1, "and generating")
end)

T.test("a map with a mesh is left alone", function()
	local s = load({ entities = SPAWNS, areas = 12 })
	Idle(s)
	T.eq(#s.seeds, 0, "not generated")
end)

T.test("an admin's run already under way is not doubled", function()
	local s = load({ entities = SPAWNS })
	s.commands.mp_nav_generate(Player(true))
	Idle(s)
	T.eq(#s.seeds, 4, "seeded once")
end)

T.test("leaving Gameplay mode to generate, it goes back after", function()
	local s = load({ entities = SPAWNS, gameplay = true })
	Idle(s)
	T.eq(s.requests[1], Gamemode.SANDBOX, "into Sandbox mode")
	s.Poll()
	s.nav.generating, s.nav.areas = false, 2133
	s.Poll()
	T.eq(s.requests[2], Gamemode.GAMEPLAY, "back to Gameplay mode")
	local sandbox = load({ entities = SPAWNS })
	Idle(sandbox)
	sandbox.Poll()
	sandbox.nav.generating, sandbox.nav.areas = false, 2133
	sandbox.Poll()
	T.eq(#sandbox.requests, 0, "in Sandbox mode already: stays there")
end)

T.test("with Sandbox mode disabled an idle server does not generate", function()
	local s = load({ entities = SPAWNS, gameplay = true, noSandbox = true })
	Idle(s)
	s.Poll()
	T.eq(s.nav.began, 0, "not generated")
	T.eq(#s.requests, 0, "the game left running")
end)

T.finish()
