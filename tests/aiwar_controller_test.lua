-- The aiwar controller's own decisions (docs/aiwar-koth-cp.md §2.10): which
-- scenario a map's rounds mode starts, the field it assembles each think,
-- how the round's winner sets the phase, and the seams through which the
-- scenario drives allocation, setup gates, lanes and guard posts. The
-- controller runs here in a fake GMod: the engine calls it makes return
-- nothing found, and the features it reads (rounds, capture, npc,
-- gamemode) are fakes that record what they are asked.
local T = dofile("tests/harness.lua")
local FP = dofile("tests/fake_points.lua")
local AiWar = T.require("foundation.aiwar")
local Orders = T.require("foundation.aiwar.orders")
local Base = T.require("foundation.aiwar.scenario")
local Payload = T.require("foundation.aiwar.scenario.payload")
local Freeform = T.require("foundation.aiwar.scenario.freeform")
local Posts = T.require("foundation.aiwar.posts")
local Lanes = T.require("foundation.aiwar.lanes")
local HL2Path = T.require("foundation.npc.path.hl2")
local Gamemode = T.require("foundation.gamemode")
local Rounds = T.require("foundation.rounds")
local PayloadMode = T.require("foundation.rounds.payload")
local ControlPointsMode = T.require("foundation.rounds.control_points")
local KothMode = T.require("features.koth.model")
local STATE = T.require("foundation.rounds.state")
local Teams = T.require("foundation.teams")
local Slots = T.require("foundation.aiwar.slots")
local Squad = T.require("foundation.aiwar.squad")
-- the real scenarios; tests of the controller alone swap in fakes
local REAL = {
	[PayloadMode.Mode.NAME] = Payload,
	[ControlPointsMode.Mode.NAME] = T.require("foundation.aiwar.scenario.control_points"),
	[KothMode.Mode.NAME] = T.require("foundation.aiwar.scenario.koth"),
}

local RED, BLUE, NOBODY = Teams.RED, Teams.BLUE, Teams.UNASSIGNED
local SOURCE = T.ROOT .. "features/aiwar/sv.lua"
local NO_SPAWNS = "this map has no spawn points for both teams, where the AI war's soldiers join the fight"
local NO_POINTS = "this map's round has no control points for the AI war to fight over"
local SOLDIERS = 8
local ZONE_INSET = 0.8 -- the controller's, docs/aiwar-koth-cp.md §2.4
local TEAM_SIZE = 8
local NOW = 100

-- Vectors ---------------------------------------------------------------------------

local Vec = {}
Vec.__index = Vec

local function Vector(x, y, z)
	return setmetatable({
		x = x or 0,
		y = y or 0,
		z = z or 0,
	}, Vec)
end

Vec.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
Vec.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
Vec.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	return Vector(a.x * b, a.y * b, a.z * b)
end
Vec.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
function Vec:DistToSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end
function Vec:Distance(o) return math.sqrt(self:DistToSqr(o)) end

local function Same(p, x, y, z, what)
	T.near(p.x, x, 1e-6, what .. " x")
	T.near(p.y, y, 1e-6, what .. " y")
	T.near(p.z, z, 1e-6, what .. " z")
end

-- Entities: a spawn point, a control point or a capture area.
local function Ent(pos, mins, maxs)
	return {
		GetPos = function() return pos end,
		GetAngles = function() return nil end,
		WorldSpaceAABB = function() return mins, maxs end,
	}
end

-- The features the controller reads -------------------------------------------------

local function Timer(left, paused)
	return {
		TimeRemaining = function() return left end,
		Paused = function() return paused end,
	}
end

-- w.timers: { hud = the HUD timer, [team] = the team's KOTH clock }, any of
-- them absent, or nil for none. A clock's entity is its team; the HUD
-- timer's is HUD_TIMER.
local HUD_TIMER = "hud timer"

local function FakeRounds(mode, w)
	local function Timers() return w.timers or {} end
	return {
		Mode = function() return mode end,
		InSuddenDeath = function() return w.suddenDeath == true end,
		CapEnableTime = function() return w.capEnableAt end,
		TeamClock = function(_, team) return Timers()[team] and team or nil end,
		TimerOf = function(_, ent) return ent == HUD_TIMER and Timers().hud or Timers()[ent] end,
		HudTimer = function() return Timers().hud and HUD_TIMER or nil end,
	}
end

local function Hud(fields)
	return {
		owner = fields.owner or NOBODY,
		locked = fields.locked or false,
		unlockTime = fields.unlockTime or 0,
		capping = fields.capping or NOBODY,
		progress = fields.progress or 0,
		blocked = fields.blocked or false,
		redCanCap = fields.redCanCap or false,
		blueCanCap = fields.blueCanCap or false,
		inRound = fields.inRound ~= false,
		hidden = fields.hidden or false,
	}
end

-- points: list of { ent, rank, hud, areas }.
local function FakeCapture(points)
	return {
		HudPoints = function()
			local list = {}
			for i, p in ipairs(points) do
				list[i] = {
					point = p.ent,
					rank = p.rank,
					hud = p.hud,
				}
			end
			return list
		end,
		AreaEntities = function(_, point)
			for _, p in ipairs(points) do
				if p.ent == point then return p.areas end
			end
			error("not a point")
		end,
	}
end

-- A fake map: its loaded features, round state and spawns, and what the
-- controller asked of it.
local function World()
	local w = {
		features = {},
		order = {},
		routes = {},
		requests = {},
		hooks = {},
		notified = {},
		convarCallbacks = {}, -- convar name -> the controller's change callback
		active = true,
		state = STATE.RND_RUNNING,
		setup = false,
		overtime = false,
		now = NOW,
		-- each side's spawn, as FP.BASES
		spawns = {
			[RED] = { Ent(Vector(FP.BASES[RED].x, FP.BASES[RED].y, 0)) },
			[BLUE] = { Ent(Vector(FP.BASES[BLUE].x, FP.BASES[BLUE].y, 0)) },
		},
		navAreas = {},
		teamSize = TEAM_SIZE,
		bools = { ns_squads_auto_enabled = true },
		ints = { ns_squads_max = 3, ns_squads_min = 3 }, -- the defaults
	}
	function w:Load(name, feature)
		self.features[name] = feature
		self.order[#self.order + 1] = name
	end
	w:Load("npc", {
		CheckNavMesh = function() end,
		RequestRoute = function(_, request) w.routes[#w.routes + 1] = request end,
		SearchesRunning = function() return 0 end,
		BlockerGeneration = function() return w.blockerGeneration or 0 end,
	})
	w:Load("gamemode", {
		Request = function(_, mode, source, _, story)
			w.requests[#w.requests + 1] = {
				mode = mode,
				source = source,
				story = story,
			}
		end,
	})
	return w
end

local function Env(w)
	-- each load's registrations, keyed as GMod keys them (T.Wiring)
	local wiring = T.Wiring()
	w.wiring = wiring
	local ws = {
		require = T.require,
		FeatureParts = T.FeatureParts,
		TEAM_RED = RED,
		TEAM_BLUE = BLUE,
		TEAM_UNASSIGNED = NOBODY,
		STATE = STATE,
		TeamName = {
			[RED] = "RED",
			[BLUE] = "BLU",
		},
		FeatureLoader = {
			Loaded = function()
				local list = {}
				for i, name in ipairs(w.order) do list[i] = name end
				return list
			end,
		},
		-- the real loader would load a missing feature: the fake refuses, so
		-- a query of a feature not loaded fails the test
		Feature = function(name) return w.features[name] or error("loaded a feature to check it: " .. name) end,
		-- the admin notices it sends (foundation.admin_notices), in order
		Notify = function(notices)
			for _, n in ipairs(notices) do w.notified[#w.notified + 1] = n.text end
		end,
		Active = function() return w.active end,
		State = function() return w.state end,
		InSetup = function() return w.setup end,
		InOvertime = function() return w.overtime end,
		SpawnPoints = function(team) return w.spawns[team] end,
		NavMeshUsable = function() return w.navUsable ~= false end,
		SoldiersEnabled = function() return w.soldiersEnabled ~= false end,
		SetTeamMember = function() end,
		ClipMasks = function() return { solid = 5, brushes = 6 } end,
	}
	local env = {
		WS = ws,
		Vector = Vector,
		DrGBase = {},
		CreateConVar = function() return {} end,
		-- the team size is w.teamSize, every other convar a bool in w.bools
		GetConVar = function(name)
			if name == "ns_squads_max" or name == "ns_squads_min" then
				return { GetInt = function() return w.ints[name] end }
			end
			if name ~= "mp_aiwar_team_size" then
				return { GetBool = function() return w.bools[name] == true end }
			end
			return {
				GetInt = function() return w.teamSize end,
				SetInt = function(_, value) w.teamSize = value end,
			}
		end,
		FCVAR_ARCHIVE = 128,
		FCVAR_NOTIFY = 256,
		cvars = {
			AddChangeCallback = function(name, fn, id)
				wiring.cvars.AddChangeCallback(name, fn, id)
				w.convarCallbacks[name] = fn
			end,
		},
		D_HT = 1,
		D_FR = 2,
		D_LI = 3,
		D_NU = 4,
		MASK_SOLID = 1,
		MASK_SOLID_BRUSHONLY = 2,
		MASK_NPCSOLID = 3,
		MASK_NPCSOLID_BRUSHONLY = 4,
		MASK_PLAYERSOLID = 5,
		MASK_PLAYERSOLID_BRUSHONLY = 6,
		NULL = false,
		IsValid = function(v) return v ~= nil and v ~= false end,
		CurTime = function() return w.now end,
		SetGlobal2Bool = function() end,
		concommand = wiring.concommand,
		hook = {
			Add = function(event, id, fn)
				wiring.hook.Add(event, id, fn)
				w.hooks[event] = fn
			end,
		},
		ents = {
			FindByClass = function() return {} end,
			GetAll = function() return {} end,
		},
		player = { GetAll = function() return {} end },
		util = {
			TraceLine = function() return { Hit = false } end,
			-- what a hull sweep hits: w.trace(t), else nothing
			TraceHull = function(t) return w.trace and w.trace(t) or { Hit = false } end,
		},
		navmesh = {
			Find = function() return w.navAreas end,
			GetNavAreaCount = function() return #w.navAreas end,
			GetAllNavAreas = function() return w.navAreas end,
		},
		table = setmetatable({
			Count = function(t)
				local n = 0
				for _ in pairs(t) do n = n + 1 end
				return n
			end,
		}, { __index = table }),
	}
	return setmetatable(env, {
		__index = function(_, name)
			local value = _G[name]
			if value == nil then error("a GMod global the fake lacks: " .. name, 2) end
			return value
		end,
	})
end

-- A slot store kept in memory, holding `saved` to begin with.
local function MemoryStore(saved)
	return {
		saved = saved,
		Read = function(self) return self.saved end,
		Write = function(self, list) self.saved = list end,
	}
end

-- A fresh controller on the fake map, its slot list kept in memory.
local function Load(w)
	local chunk = assert(loadfile(SOURCE))
	local controller = setfenv(chunk, Env(w))()
	controller.slotStore = MemoryStore()
	return controller
end

-- A scenario variant standing in for package B's, registered for a rounds
-- mode: Brief puts parts.objectives(field) on the field; Stances,
-- Front and SetupAttacks answer from parts; Reset is counted.
local function FakeVariant(mode, parts)
	local V = Base.Scenario:Extend(mode.NAME)
	V.GUARDS_ALL_ROUND = parts.guardsAllRound or false
	function V:Brief(field)
		field.doctrine = Orders.PAYLOAD
		field.objectives = parts.objectives and parts.objectives(field) or nil
	end
	function V:Stances() return parts.stances or {}, parts.defense or {} end
	function V:Front(_, team) return parts.fronts and parts.fronts[team] end
	function V:SetupAttacks() return parts.attacks or {} end
	function V:Reset()
		Base.Scenario.Reset(self)
		self.resets = (self.resets or 0) + 1
	end
	package.loaded[Base.VARIANTS[mode.NAME]] = { Scenario = V }
	return V
end

-- The mode's own scenario, package B's.
local function RealVariant(mode)
	package.loaded[Base.VARIANTS[mode.NAME]] = REAL[mode.NAME]
	return REAL[mode.NAME].Scenario
end

-- parts: a fake variant's (FakeVariant); nil for the mode's own.
local function Started(w, mode, parts)
	if parts then FakeVariant(mode, parts) elseif REAL[mode.NAME] then RealVariant(mode) end
	w:Load("rounds", FakeRounds(mode, w))
	local controller = Load(w)
	T.eq(select(2, controller:Start()), nil, "no refusal")
	return controller
end

-- Slots: each faction's size, and mp_aiwar_slots_* ----------------------------------

local function SlotIds(controller, team)
	local ids = {}
	for i, slot in ipairs(controller:SlotPlan():Slots(controller:FactionName(team))) do ids[i] = slot.id end
	return ids
end

T.test("at a team size, every faction keeps that many slots, and the list is kept", function()
	local w = World()
	w.teamSize = 3
	local controller = Load(w)
	controller.slotStore = MemoryStore()
	local sizes = controller:Sizes()
	T.eq(sizes[RED] .. " " .. sizes[BLUE], "3 3", "three a side")
	T.eq(#controller.slotStore.saved.Combine, 3, "kept")
	w.teamSize = 1
	sizes = controller:Sizes()
	T.eq(sizes[RED] .. " " .. sizes[BLUE], "1 1", "follows the team size")
end)

T.test("setting a side's slot count sizes that side alone, and turns the team size to the slot list's", function()
	local w = World()
	w.teamSize = 2
	local controller = Load(w)
	controller:SetSlotCount(RED, 5)
	T.eq(w.teamSize, Slots.CUSTOM_SIZE, "the slot list rules")
	local sizes = controller:Sizes()
	T.eq(sizes[RED] .. " " .. sizes[BLUE], "5 2", "RED has five")
	controller:SetSlotCount(BLUE, 0)
	sizes = controller:Sizes()
	T.eq(sizes[RED] .. " " .. sizes[BLUE], "5 0", "RED alone")
	T.eq(#controller.slotStore.saved.Resistance, 0, "kept empty")
end)

T.test("removing slots by id removes their soldiers, and sets that side's size", function()
	local w = World()
	w.teamSize = 3
	local controller = Load(w)
	controller:Sizes()
	local removed = false
	controller:SlotPlan():Fill("Combine", { Remove = function() removed = true end })
	local ids = SlotIds(controller, RED)
	local lines = controller:RemoveSlots({ ids[1], ids[2], 99 })
	T.eq(removed, true, "the soldier in the first went with it")
	T.eq(w.teamSize, Slots.CUSTOM_SIZE, "the slot list rules")
	local sizes = controller:Sizes()
	T.eq(sizes[RED] .. " " .. sizes[BLUE], "1 3", "RED has one left")
	T.eq(lines[3], "mp_aiwar_slots_remove: no slot 99", "an unknown slot is told")
end)

T.test("pins are kept with the slot list, and read back on the next map", function()
	local w = World()
	w.teamSize = 2
	local controller = Load(w)
	controller.slotStore = MemoryStore()
	controller:Sizes()
	local first = SlotIds(controller, RED)[1]
	T.eq(controller:PinSlots("mp_aiwar_slots_leader", { first }, Squad.LEADER)[1], "mp_aiwar_slots_leader: slot " .. first .. " leader", "told")
	local saved = controller.slotStore.saved
	w.teamSize = Slots.CUSTOM_SIZE
	local next = Load(w)
	next.slotStore = MemoryStore(saved)
	local sizes = next:Sizes()
	T.eq(sizes[RED] .. " " .. sizes[BLUE], "2 2", "the same slots")
	T.eq(next:SlotPlan():Slots("Combine")[1].pin, Squad.LEADER, "the same pin")
end)

-- A soldier the controller holds, with entity index `index`, whose DrGBase
-- AI can be turned off.
local function FakeSoldier(index)
	return {
		EntIndex = function() return index end,
		SetAIDisabled = function(self, off) self.aiOff = off end,
	}
end

-- Bug: aiwar/sv.lua lost IsDoor in a refactor; every soldier held at one
-- spot raised "attempt to call global 'IsDoor'" each tick.
T.test("a soldier held up by a door in its way finds the door", function()
	local w = World()
	local controller = Started(w, PayloadMode.Mode)
	local door = Ent(Vector(50, 0, 0))
	door.GetClass = function() return "func_door" end
	local soldier = FakeSoldier(1)
	soldier.GetClass = function() return "ws_drg_rebel" end
	soldier.GetPos = function() return Vector(0, 0, 0) end
	soldier.IsNextBot = function() return false end
	soldier.SetFactionRelationship = function() end
	controller:Enlist(soldier, BLUE, false)
	w.trace = function() return { Hit = true, HitWorld = false, Entity = door } end
	T.eq(controller.soldiers[soldier].soldier:DoorAhead({ x = 100, y = 0, z = 0 }), door, "the door")
end)

-- A controller over a war of n BLU soldiers (entity indexes 1 to n).
local function Squadded(n)
	local w = World()
	local controller = Load(w)
	controller.war = AiWar.War.New()
	controller.war:Assign({ [BLUE] = true })
	local ents = {}
	for i = 1, n do
		ents[i] = FakeSoldier(i)
		controller.war:Enlist(ents[i], BLUE, false)
		controller.soldiers[ents[i]] = {}
	end
	return controller, ents, w
end

T.test("pausing turns every soldier's AI off, and resuming on", function()
	local controller, ents = Squadded(2)
	controller:SetPaused(true)
	T.eq(ents[1].aiOff and ents[2].aiOff, true, "off")
	T.eq(controller.paused, true, "paused")
	controller:SetPaused(false)
	T.eq(ents[1].aiOff or ents[2].aiOff, false, "on again")
end)

T.test("a squad formed from soldiers by entity index is led by the first; others join it, and leave it", function()
	local controller, ents = Squadded(6)
	controller:FormSquadOf({ 3, 1, 2 })
	local leader = controller.war:Member(ents[3])
	T.eq(controller.war:Member(ents[1]).fireTeam, leader.fireTeam, "1 with 3")
	T.eq(Squad.Leader(leader.fireTeam), leader, "3 leads")
	controller:JoinSquadOf(3, { 4, 5 })
	T.eq(#controller.war:FireTeamMembers(leader.fireTeam), 5, "five in it")
	controller.war:SetAutoSquads(false)
	controller:LeaveSquadOf({ 5 })
	T.eq(controller.war:Member(ents[5]).fireTeam, nil, "5 solo")
	T.eq(controller:FormSquadOf({ 9 })[1], "ns_squads_form: #9 is no soldier of the war", "an unknown soldier is told")
	T.eq(controller:JoinSquadOf(6, { 1 })[1] ~= nil, true, "joining a soldier's squad when it is in one")
end)

T.test("jobs given by hand must be the scenario's, and are handed back to the war", function()
	local controller, ents = Squadded(2)
	controller.war:SetField({ doctrine = { ROLES = { [AiWar.RAID] = {}, [AiWar.DEFEND] = {} } } })
	T.eq(table.concat(controller:Jobs(), " "), "defend raid", "the doctrine's jobs, sorted")
	controller:AssignJob(AiWar.RAID, { 1 })
	T.eq(controller.war:Member(ents[1]).role, AiWar.RAID, "raids")
	T.eq(controller:AssignJob("dance", { 1 })[1], "ns_jobs_assign: dance is no job here (defend, raid)", "refused")
	controller:ReleaseJob({ 1 })
	T.eq(controller.war:Member(ents[1]).roleByHand, nil, "the war's again")
end)

T.test("a stored slot list that is none is replaced by a new one", function()
	local w = World()
	w.teamSize = Slots.CUSTOM_SIZE
	local controller = Load(w)
	controller.slotStore = MemoryStore({ Combine = { "captain" } })
	local sizes = controller:Sizes()
	T.eq(sizes[RED] .. " " .. sizes[BLUE], "0 0", "no slots")
end)

-- Riding the cart: ws_aiwar_sitting_enabled ------------------------------------

-- A soldier port that is seated or not; Stand gets it off, as the real one.
local function SeatedPort(seated)
	return { seat = seated and {} or nil, Stand = function(self) self.seat = nil end }
end

T.test("turning sitting off stands every seated soldier, and turning it on stands none", function()
	local w = World()
	local controller = Load(w)
	local riding, walking = SeatedPort(true), SeatedPort(false)
	controller.soldiers = { a = { soldier = riding }, b = { soldier = walking } }
	local changed = w.convarCallbacks.ws_aiwar_sitting_enabled
	T.eq(type(changed), "function", "the controller follows the convar")
	changed("ws_aiwar_sitting_enabled", "0", "1")
	T.eq(riding.seat ~= nil, true, "still riding after sitting was turned on")
	changed("ws_aiwar_sitting_enabled", "1", "0")
	T.eq(riding.seat, nil, "off the cart")
	T.eq(walking.seat, nil, "the walker stays on foot")
end)

-- Starting: the scenario from the rounds mode ---------------------------------------

-- One nav area at the origin: waypoints for freeform's explorers.
local function OneNavArea(w)
	w.navAreas = { { GetCenter = function() return Vector(0, 0, 0) end } }
end

T.test("a map without rounds loaded is fought freeform, in its bigger squads", function()
	local w = World()
	OneNavArea(w)
	local controller = Load(w)
	T.eq(select(2, controller:Start()), nil, "no refusal")
	T.eq(getmetatable(controller.scenario), Freeform.Scenario, "the freeform variant")
	T.eq(controller.war.fireTeamSize, Freeform.Scenario.SQUAD_SIZE, "its squads")
	T.eq(#w.requests, 1, "Gameplay mode asked for")
end)

T.test("a rounds mode without a standard objective is fought freeform; without a nav mesh it is refused", function()
	local w = World()
	OneNavArea(w)
	w:Load("rounds", FakeRounds(Rounds.Mode, w))
	local controller = Load(w)
	T.eq(select(2, controller:Start()), nil, "no refusal")
	T.eq(getmetatable(controller.scenario), Freeform.Scenario, "the freeform variant")
	local bare = World()
	bare:Load("rounds", FakeRounds(Rounds.Mode, bare))
	local ok, why = Load(bare):Start()
	T.eq(ok, false, "refused")
	T.eq(why:find("mp_nav_generate", 1, true) ~= nil, true, "why: " .. tostring(why))
end)

T.test("the war still needs DrGBase first", function()
	local w = World()
	w:Load("rounds", FakeRounds(PayloadMode.Mode, w))
	local env = Env(w)
	env.DrGBase = false
	local chunk = assert(loadfile(SOURCE))
	local ok, why = setfenv(chunk, env)():Start()
	T.eq(ok, false, "refused")
	T.eq(why:find("DrGBase", 1, true) ~= nil, true, "why: " .. tostring(why))
end)

T.test("with NextSoldier switched off (ns_soldiers_enabled 0) the war is refused, and says why", function()
	local w = World()
	w.soldiersEnabled = false
	w:Load("rounds", FakeRounds(PayloadMode.Mode, w))
	local chunk = assert(loadfile(SOURCE))
	local ok, why = setfenv(chunk, Env(w))():Start()
	T.eq(ok, false, "refused")
	T.eq(why:find("ns_soldiers_enabled", 1, true) ~= nil, true, "why: " .. tostring(why))
end)

T.test("a map with no usable navigation mesh is refused, and the admin is told how to make one", function()
	local w = World()
	w:Load("rounds", FakeRounds(PayloadMode.Mode, w))
	w.navUsable = false
	local ok, why = Load(w):Start()
	T.eq(ok, false, "refused")
	T.eq(why:find("mp_nav_generate", 1, true) ~= nil, true, "why: " .. tostring(why))
end)

T.test("a payload map starts the payload scenario, asks for Gameplay mode, and loads no other scenario", function()
	local w = World()
	-- as on a fresh map: no point scenario loaded
	for _, mode in ipairs({ ControlPointsMode.Mode, KothMode.Mode }) do package.loaded[Base.VARIANTS[mode.NAME]] = nil end
	local controller = Started(w, PayloadMode.Mode)
	T.eq(getmetatable(controller.scenario), Payload.Scenario, "the payload variant")
	T.eq(#w.requests, 1, "one request")
	T.eq(w.requests[1].mode, Gamemode.GAMEPLAY, "Gameplay mode")
	T.eq(w.requests[1].source, Gamemode.SOURCE_AI_WAR, "as the AI war")
	T.eq(type(w.requests[1].story.announcement), "string", "an announcement")
	T.eq(package.loaded[Base.VARIANTS[KothMode.Mode.NAME]], nil, "no koth scenario")
	T.eq(package.loaded[Base.VARIANTS[ControlPointsMode.Mode.NAME]], nil, "no control point scenario")
	T.eq(select(2, controller:Start()), "the war is already on", "once")
end)

-- A capture feature with one point, neutral and capturable by both, its
-- area FP.RADIUS / ZONE_INSET either side of the origin.
local HALF = FP.RADIUS / ZONE_INSET

local function OnePoint(w, fields)
	fields = fields or {
		redCanCap = true,
		blueCanCap = true,
	}
	local point = {
		ent = Ent(Vector(0, 0, 0)),
		rank = 0,
		hud = Hud(fields),
		areas = { Ent(nil, Vector(-HALF, -HALF, 0), Vector(HALF, HALF, 128)) },
	}
	w:Load("capture", FakeCapture({ point }))
	return point
end

T.test("control point and KOTH maps start their own scenario", function()
	for _, mode in ipairs({ ControlPointsMode.Mode, KothMode.Mode }) do
		local w = World()
		OnePoint(w)
		local controller = Started(w, mode)
		T.eq(getmetatable(controller.scenario), REAL[mode.NAME].Scenario, mode.NAME)
	end
end)

T.test("the point scenarios refuse a map whose round has no points", function()
	for _, mode in ipairs({ ControlPointsMode.Mode, KothMode.Mode }) do
		RealVariant(mode)
		local w = World()
		w:Load("rounds", FakeRounds(mode, w))
		local ok, why = Load(w):Start()
		T.eq(ok, false, mode.NAME .. ": no capture feature")
		T.eq(why, NO_POINTS, mode.NAME)
		w:Load("capture", FakeCapture({}))
		T.eq(select(2, Load(w):Start()), NO_POINTS, mode.NAME .. ": no points")
	end
end)

T.test("any scenario refuses a map without both teams' spawns", function()
	for _, mode in ipairs({ PayloadMode.Mode, ControlPointsMode.Mode }) do
		RealVariant(mode)
		local w = World()
		OnePoint(w)
		w.spawns[BLUE] = {}
		w:Load("rounds", FakeRounds(mode, w))
		local controller = Load(w)
		local ok, why = controller:Start()
		T.eq(ok, false, mode.NAME .. ": refused")
		T.eq(why, NO_SPAWNS, mode.NAME)
		T.eq(controller.war, nil, mode.NAME .. ": no war")
	end
end)

T.test("starting and ending the war tells everyone visitors arrived and left", function()
	local w = World()
	local controller = Started(w, PayloadMode.Mode)
	T.eq(w.notified[#w.notified], "Visitors from another universe have arrived!")
	controller:End()
	T.eq(w.notified[#w.notified], "The visitors have returned to their own universe.")
end)

T.test("an ended war can start again, with a new scenario", function()
	local controller = Started(World(), PayloadMode.Mode)
	local first = controller.scenario
	T.eq(controller:End(), true, "ended")
	T.eq(controller.scenario, nil, "no scenario")
	T.eq(controller:Start(), true, "started again")
	T.eq(controller.scenario ~= first, true, "a new instance")
end)

-- The field -------------------------------------------------------------------------

T.test("every think's field carries the scenario's doctrine and the round's phase", function()
	local controller = Started(World(), PayloadMode.Mode)
	local field = controller:Survey(NOW)
	T.eq(field.doctrine, Orders.PAYLOAD, "the payload doctrine")
	T.eq(field.phase, AiWar.PHASES.running, "running")
	T.eq(next(field.carts), nil, "no carts")
	T.eq(field.winner, nil, "no winner")
	T.eq(field.overtime, false, "not overtime")
	T.eq(field.points, nil, "capture not loaded: no points")
end)

T.test("the field's points are what the capture HUD shows, with where each point is", function()
	local w = World()
	local mid = Ent(Vector(0, 0, 10))
	local last = Ent(Vector(900, 0, 20))
	w:Load("capture", FakeCapture({
		{
			ent = mid,
			rank = 0,
			hud = Hud({
				owner = RED,
				capping = BLUE,
				progress = 0.25,
				blocked = true,
				blueCanCap = true,
			}),
			-- two areas: their union is 400 by 200, from z 0
			areas = {
				Ent(nil, Vector(-200, -100, 0), Vector(0, 100, 128)),
				Ent(nil, Vector(0, -50, 0), Vector(200, 50, 64)),
			},
		},
		{
			ent = last,
			rank = 1,
			hud = Hud({
				locked = true,
				unlockTime = 130,
				inRound = false,
				hidden = true,
			}),
			areas = {},
		},
	}))
	local controller = Started(w, ControlPointsMode.Mode, {})
	local points = controller:Survey(NOW).points
	T.eq(#points, 2, "two points")
	local a, b = points[1], points[2]
	T.eq(a.id, mid, "the point entity")
	T.eq(a.rank, 0, "rank")
	Same(a.pos, 0, 0, 10, "pos")
	Same(a.zone.center, 0, 0, 0, "zone center")
	T.near(a.zone.radius, ZONE_INSET * 100, 1e-6, "zone radius: the smaller half extent, inset")
	T.eq(a.owner, RED, "owner")
	T.eq(a.locked, false, "unlocked")
	T.eq(a.unlockAt, nil, "no unlock time")
	T.eq(a.capping, BLUE, "capping")
	T.eq(a.progress, 0.25, "progress")
	T.eq(a.blocked, true, "blocked")
	T.eq(a.mayCapture[RED], false, "RED may not")
	T.eq(a.mayCapture[BLUE], true, "BLU may")
	T.eq(a.inRound, true, "in round")
	T.eq(a.hidden, false, "shown")
	T.eq(b.rank, 1, "rank")
	T.eq(b.zone, nil, "no areas: no zone")
	T.eq(b.owner, NOBODY, "neutral")
	T.eq(b.locked, true, "locked")
	T.eq(b.unlockAt, 130, "unlocks at")
	T.eq(b.capping, NOBODY, "nobody caps")
	T.eq(b.inRound, false, "out of round")
	T.eq(b.hidden, true, "hidden")
end)

T.test("clocks and time left come from the rounds' timers", function()
	local w = World()
	w.timers = {
		hud = Timer(240, false),
		[RED] = Timer(170, true),
		[BLUE] = Timer(25, false),
	}
	w.overtime = true
	local field = Started(w, KothMode.Mode, {}):Survey(NOW)
	T.eq(field.timeLeft, 240, "the HUD timer's time left")
	T.eq(field.clocks[RED].left, 170, "RED's clock")
	T.eq(field.clocks[RED].running, false, "paused")
	T.eq(field.clocks[BLUE].left, 25, "BLU's clock")
	T.eq(field.clocks[BLUE].running, true, "running")
	T.eq(field.overtime, true, "overtime")
end)

T.test("without timers there is no time left and no clocks", function()
	local field = Started(World(), ControlPointsMode.Mode, {}):Survey(NOW)
	T.eq(field.timeLeft, nil, "no time left")
	T.eq(field.clocks, nil, "no clocks")
end)

T.test("each team's base is the centroid of its spawns, kept until the next round", function()
	local w = World()
	w.spawns[RED] = {
		Ent(Vector(0, 0, 0)),
		Ent(Vector(100, 200, 30)),
	}
	w.spawns[BLUE] = { Ent(Vector(-500, 0, 0)) }
	local controller = Started(w, ControlPointsMode.Mode, {})
	local field = controller:Survey(NOW)
	Same(field.bases[RED], 50, 100, 15, "RED's base")
	Same(field.bases[BLUE], -500, 0, 0, "BLU's base")
	T.eq(#field.spawns[RED], 2, "RED's spawns")
	Same(field.spawns[RED][2], 100, 200, 30, "a spawn")
	w.spawns[BLUE] = { Ent(Vector(-900, 0, 0)) }
	Same(controller:Survey(NOW).bases[BLUE], -500, 0, 0, "cached")
	w.hooks.WSRoundActivate()
	Same(controller:Survey(NOW).bases[BLUE], -900, 0, 0, "the next round's")
end)

-- The phase and the winner ----------------------------------------------------------

T.test("a round won by a team is its humiliation, until the next round resets the scenario", function()
	local w = World()
	local controller = Started(w, ControlPointsMode.Mode, {})
	w.state = STATE.TEAM_WIN
	w.hooks.WSRoundWin(BLUE)
	local field = controller:Survey(NOW)
	T.eq(field.phase, AiWar.PHASES.humiliation, "humiliation")
	T.eq(field.winner, BLUE, "BLU won")
	T.eq(controller.losers, RED, "RED humiliated")
	w.state = STATE.PREROUND
	w.hooks.WSRoundActivate()
	field = controller:Survey(NOW)
	T.eq(field.winner, nil, "no winner")
	T.eq(field.phase, AiWar.PHASES.frozen, "frozen")
	T.eq(controller.scenario.resets, 1, "the scenario reset")
end)

T.test("a defenders' win has the factions trade sides with the next round; an attackers' keeps them", function()
	local w = World()
	local controller = Started(w, ControlPointsMode.Mode, {})
	w.state = STATE.TEAM_WIN
	w.hooks.WSRoundWin(RED, Rounds.WINREASON.ALL_POINTS_CAPTURED)
	w.hooks.WSRoundActivate()
	T.eq(controller.war:Faction(RED).name, "Combine", "an attackers' win changes nothing")
	w.hooks.WSRoundWin(RED, Rounds.WINREASON.DEFEND_UNTIL_TIME_LIMIT)
	T.eq(controller.war:Faction(RED).name, "Combine", "the sides hold through the humiliation")
	w.hooks.WSRoundActivate()
	T.eq(controller.war:Faction(RED).name, "Resistance", "the Resistance on RED")
	T.eq(controller.war:Faction(BLUE).name, "Combine", "the Combine attack as BLU")
end)

T.test("arena's round is the arena phase; a sudden death after it is sudden death's", function()
	local w = World()
	local controller = Started(w, T.require("foundation.rounds.arena").Mode, {})
	w.active, w.state = true, STATE.STALEMATE
	T.eq(controller:Survey(NOW).phase, AiWar.PHASES.arena, "the arena round")
	w.suddenDeath = true
	T.eq(controller:Survey(NOW).phase, AiWar.PHASES.suddenDeath, "its sudden death")
end)

T.test("a stalemate has no winner, so the round is over and nobody hunts", function()
	local w = World()
	local controller = Started(w, ControlPointsMode.Mode, {})
	w.state = STATE.TEAM_WIN
	w.hooks.WSRoundWin(NOBODY)
	local field = controller:Survey(NOW)
	T.eq(field.winner, nil, "no winner")
	T.eq(field.phase, AiWar.PHASES.over, "over")
	T.eq(controller.losers, nil, "nobody humiliated")
end)

-- The scenario seams ----------------------------------------------------------------

T.test("the scenario allocates every think: its stances and defense shares reach the war", function()
	local stance = {
		{
			role = AiWar.HOLD,
			weight = 1,
		},
	}
	local controller = Started(World(), ControlPointsMode.Mode, {
		stances = {
			[RED] = {
				stance = stance,
				key = "held",
			},
		},
		defense = { [RED] = 1 },
	})
	local field = controller:Survey(NOW)
	T.eq(controller.war.stances[RED], stance, "RED's stance")
	T.eq(controller.war.stances[BLUE], nil, "BLU left as it is")
	T.eq(controller.war.defense[RED], 1, "RED's defense share")
	T.eq(field.defense, nil, "the war writes field.defense in SetField")
end)

T.test("in setup, gates are looked for toward the scenario's setup attacks, once a round", function()
	local w = World()
	w.setup = true
	w.spawns[BLUE] = {
		Ent(Vector(0, 0, 0)),
		Ent(Vector(300, 0, 0)),
	}
	local controller = Started(w, ControlPointsMode.Mode, {
		attacks = {
			[BLUE] = {
				x = 1000,
				y = 0,
				z = 0,
			},
		},
	})
	controller:Survey(NOW)
	local gates = {}
	for _, r in ipairs(w.routes) do
		if r.strategy == HL2Path then gates[#gates + 1] = r end
	end
	T.eq(#gates, 2, "a route from each far spawn")
	T.eq(gates[1].to.x, 1000, "toward the attack")
	T.eq(gates[1].bot.team, BLUE, "BLU's")
	controller:Survey(NOW)
	T.eq(#w.routes, 2, "not again this round")
end)

T.test("lanes lead to the scenario's front", function()
	local w = World()
	w.spawns[RED] = { Ent(Vector(0, 0, 0)) }
	w.spawns[BLUE] = { Ent(Vector(2000, 0, 0)) }
	Started(w, ControlPointsMode.Mode, {
		fronts = {
			[RED] = {
				x = 1000,
				y = 0,
				z = 0,
			},
		},
	}):Survey(NOW)
	T.eq(#w.routes, 1, "one lane search")
	T.eq(w.routes[1].strategy, Lanes.Strategy, "a lane")
	T.eq(w.routes[1].bot.team, RED, "RED's")
	T.eq(w.routes[1].to.x, 1000, "to RED's front")
end)

-- A setup gate opening, or a door shutting, changes the doors' blockers:
-- lanes planned around the old ones are planned again at once.
T.test("lanes are planned again when the doors' blockers change", function()
	local w = World()
	w.spawns[RED] = { Ent(Vector(0, 0, 0)) }
	w.spawns[BLUE] = { Ent(Vector(2000, 0, 0)) }
	local controller = Started(w, ControlPointsMode.Mode, { fronts = { [RED] = { x = 1000, y = 0, z = 0 } } })
	controller:Survey(NOW)
	-- every lane's search finds no route (a shut gate), so the plan ends
	local answered = 0
	while w.routes[answered + 1] do
		answered = answered + 1
		w.routes[answered].onDone(nil)
	end
	controller:Survey(NOW)
	T.eq(#w.routes, answered, "nothing changed: no new plan")
	w.blockerGeneration = 1
	controller:Survey(NOW)
	T.eq(#w.routes, answered + 1, "the gate opened: planned again")
end)

-- Package B's guard scoring and range (docs/aiwar-koth-cp.md §3): the test
-- records the candidates the controller scores.
T.test("each team's guard point gets posts round it, scored as guard posts", function()
	local w = World()
	w.spawns[RED] = { Ent(Vector(-1000, 0, 0)) }
	w.spawns[BLUE] = { Ent(Vector(1000, 0, 0)) }
	w.navAreas = {
		{
			GetHidingSpots = function(_, flag) return flag == 1 and { Vector(-300, 0, 0) } or {} end,
			GetCenter = function() return Vector(0, 0, 0) end,
		},
	}
	local guard = {
		id = "A",
		rank = 0,
		zone = {
			center = {
				x = 0,
				y = 0,
				z = 0,
			},
			radius = 100,
		},
	}
	local scored = {}
	local scoreGuard, range = Posts.ScoreGuard, Posts.MAX_GUARD_RANGE
	Posts.ScoreGuard = function(c)
		scored[#scored + 1] = c
		return 1
	end
	Posts.MAX_GUARD_RANGE = range or 1250
	local ok, err = pcall(function()
		local field = Started(w, ControlPointsMode.Mode, {
			guardsAllRound = true,
			objectives = function()
				return {
					[RED] = { guard = guard },
					[BLUE] = {},
				}
			end,
		}):Survey(NOW)
		T.eq(#field.posts[RED], 1, "RED's post")
		Same(field.posts[RED][1], -300, 0, 0, "the hiding spot")
		T.eq(field.posts[BLUE], nil, "BLU guards nothing")
		T.eq(#scored, 1, "one candidate")
		local c = scored[1]
		T.eq(c.sees, true, "sees the point")
		T.eq(c.toPoint, 300, "to the point")
		T.eq(c.elevation, 0, "level")
		T.eq(c.cover, true, "in cover")
		T.eq(c.past, -300, "short of the point from RED's base")
		T.eq(c.anywhere, true, "the scenario's GUARDS_ALL_ROUND")
	end)
	Posts.ScoreGuard, Posts.MAX_GUARD_RANGE = scoreGuard, range
	assert(ok, err)
end)

T.test("the report names each team's scenario, stance and objectives", function()
	local point = function(rank) return { rank = rank } end
	local controller = Started(World(), ControlPointsMode.Mode, {
		stances = {
			[RED] = {
				stance = {
					{
						role = AiWar.CAPTURE,
						weight = 1,
					},
				},
				key = "lost:4",
			},
		},
		objectives = function()
			return {
				[RED] = {
					target = point(2),
					staging = point(3),
				},
				[BLUE] = { guard = point(2) },
			}
		end,
	})
	controller.war:SetField(controller:Survey(NOW))
	local text = table.concat(controller:Report(), "\n")
	local name = ControlPointsMode.Mode.NAME
	T.eq(text:find("RED " .. name .. ": stance lost:4, target 2, guard -, staging 3", 1, true) ~= nil, true, text)
	T.eq(text:find("BLU " .. name .. ": stance -, target -, guard 2, staging -", 1, true) ~= nil, true, text)
end)

-- The seam: the controller's think with package B's scenarios --------------------
-- A tests/fake_points.lua battle whose think is the controller's: the
-- controller builds the field and commands, and hands the war the field
-- the battle's fake soldiers act on.

local function ControllerBattle(w, mode)
	w.teamSize = 0 -- the battle's soldiers only
	local controller = Started(w, mode)
	local battle = FP.Battle(REAL[mode.NAME].Scenario)
	battle.war, battle.scenario = controller.war, controller.scenario
	function battle:Command()
		w.now = self.now
		controller.nextThink = 0
		controller:Think(self.now)
	end
	battle:Enlist(RED, SOLDIERS)
	battle:Enlist(BLUE, SOLDIERS)
	return battle, controller
end

local function OnHill(battle, team)
	local hill = battle.war:Field().points[1]
	local capturers = battle:Of(team, AiWar.CAPTURE)
	T.eq(#capturers > 0, true, team .. " has capturers")
	for _, s in ipairs(capturers) do
		T.eq(FP.InZone(s.me.pos, hill), true, s.member.handle .. " on the hill")
	end
end

-- Whether the soldier's stack runs the action (a trip buries the action
-- that took it, in Describe).
local function Runs(npc, name)
	local _, frames = npc:Stack()
	for _, frame in ipairs(frames) do
		if frame.name == name then return true end
	end
	return false
end

local function Hunting(battle, team)
	for _, s in ipairs(battle.soldiers) do
		if s.member.team == team then
			T.eq(Runs(s.npc, "SeekAndDestroy"), true, s.member.handle .. ": " .. s.npc:Describe())
		end
	end
end

local TRIP_TICKS = 45 -- base to hill, FP.SPEED, and a few shuffles

T.test("KOTH through the controller: Sandbox waits for the clocks, the round brings commands, a won round is a hunt", function()
	local w = World()
	w.active = false -- Sandbox mode: no KOTH round, so no clocks
	OnePoint(w)
	local battle, controller = ControllerBattle(w, KothMode.Mode)
	local Koth = REAL[KothMode.Mode.NAME]
	battle:Command()
	T.eq(controller.waitingFor, Base.CLOCKS, "waiting for the clocks")
	T.eq(battle.war:Field(), nil, "no field for the soldiers")
	T.eq(next(battle.war.stances), nil, "no commands")
	T.eq(next(controller.scenario.current), nil, "nothing allocated")
	-- the countdown ends: the KOTH round spawns its clocks and runs
	w.active, w.state = true, STATE.RND_RUNNING
	w.timers = {
		[RED] = Timer(Koth.KOTH_TURTLE_TIME * 6, true),
		[BLUE] = Timer(Koth.KOTH_TURTLE_TIME * 6, true),
	}
	battle:Start()
	T.eq(controller.waitingFor, nil, "a whole field")
	T.eq(battle.war:Field().doctrine, REAL[ControlPointsMode.Mode.NAME].DOCTRINE, "the point doctrine")
	T.eq(controller.scenario.current[RED].key, Koth.OPEN, "RED: an open hill")
	T.eq(controller.scenario.current[BLUE].key, Koth.OPEN, "BLU: an open hill")
	battle:Tick(nil, TRIP_TICKS)
	OnHill(battle, RED)
	OnHill(battle, BLUE)
	-- BLU wins: its soldiers hunt RED's
	w.state = STATE.TEAM_WIN
	w.hooks.WSRoundWin(BLUE)
	battle:Tick(nil, 2)
	T.eq(battle.war:Field().phase, AiWar.PHASES.humiliation, "humiliation")
	Hunting(battle, BLUE)
	-- the next round: the hunt is over, and the clocks are made again
	w.timers = nil
	w.state = STATE.PREROUND
	w.hooks.WSRoundActivate()
	battle:Tick(nil, 2)
	T.eq(controller.waitingFor, Base.CLOCKS, "between the clocks")
	w.timers = {
		[RED] = Timer(Koth.KOTH_TURTLE_TIME * 6, true),
		[BLUE] = Timer(Koth.KOTH_TURTLE_TIME * 6, true),
	}
	battle:Tick(nil, 2)
	T.eq(battle.war:Field().phase, AiWar.PHASES.frozen, "frozen")
	T.eq(battle.war:Field().winner, nil, "no winner")
	for _, s in ipairs(battle.soldiers) do
		T.eq(Runs(s.npc, "SeekAndDestroy"), false, s.member.handle .. " stopped hunting")
	end
end)

T.test("control points through the controller: commands from the first think, both sides take mid, a won round is a hunt", function()
	local w = World()
	w.active = false -- Sandbox mode: CP awaits nothing
	OnePoint(w)
	local battle, controller = ControllerBattle(w, ControlPointsMode.Mode)
	battle:Start()
	T.eq(controller.waitingFor, nil, "a whole field")
	T.eq(battle.war:Field().objectives[RED].target.rank, 0, "RED's target: mid")
	T.eq(battle.war:Field().objectives[BLUE].target.rank, 0, "BLU's target: mid")
	battle:Tick(nil, TRIP_TICKS)
	OnHill(battle, RED)
	OnHill(battle, BLUE)
	w.active, w.state = true, STATE.TEAM_WIN
	w.hooks.WSRoundWin(RED)
	battle:Tick(nil, 2)
	Hunting(battle, RED)
end)

-- GMod replaces a hook, command, callback, timer or listener registered
-- again under the same key, so one registration would silently drop
-- another.
T.test("registers each wiring key once", function()
	local w = World()
	Load(w)
	T.eq(#w.wiring:Registered() > 20, true, "the registrations were recorded")
	T.eq(table.concat(w.wiring:Duplicates(), ", "), "", "keys registered twice")
end)

T.test("the controller never reads the map's name for its scenario", function()
	local text = T.RealmSource("aiwar", "sv")
	T.eq(text:find("this map has no payload cart", 1, true), nil, "no cart refusal")
	T.eq(text:find("function Controller:CartTeams", 1, true), nil, "CartTeams moved to the payload variant")
	for _, name in ipairs({ "game.GetMap", '"koth_', '"cp_', '"pl_' }) do
		T.eq(text:find(name, 1, true), nil, name)
	end
end)

T.finish()
