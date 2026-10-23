-- The npc feature's controller. It owns one games.npc.nextbot Npc per NPC
-- entity, the features.npc.spawner models, a registry by kind and the
-- per-variant shared state, and checks the navigation mesh once per map.
-- The rules live in the models; this file only feeds them engine events and
-- turns their answers into entities.
--
-- This root holds the state, binding, spawning, bosses and the wiring that
-- spans parts; its parts are sv_blockers (spawn rooms and the blockers on
-- the nav mesh), sv_routes (path costs, the nav graph, route searches and
-- waypoints) and sv_profile (path profiling, watching and the bench).
local NpcSystem = npc.nextbot
local Scheduler = list.schedule
local Spawner = WS.require("features.npc.spawner")

local NAV_MESSAGE = "ws_nextbot: %s has no usable navigation mesh; run mp_nav_generate (or .devtools/bin/nav_convert.py for TF2's own)"
local BOSS_HEALTH = "ws_boss_health" -- the boss bar's fraction; 0 hides it

local Controller = {
	npcs = {}, -- entity -> Npc
	variantNames = {}, -- entity -> variant name
	kinds = {}, -- kind -> { [entity] = true }
	shared = {}, -- variant name -> table
	precached = {}, -- variant name -> true once its particle systems are precached
	spawners = {}, -- spawner entity -> Spawner
	spawnedBy = {}, -- NPC entity -> Spawner
	navChecked = false,
	pathProfile = nil, -- a features.npc.profile while ws_path_profile's window is open
	pathWatch = {}, -- entity index -> { costs } while the nbdebug feature watches its path searches
	spawnRoomTeams = {}, -- nav area id -> the team whose spawn room holds it, this round
	searches = Scheduler.New({ Now = function() return SysTime() end }), -- the Lua route searches still running, each a task
	neighbors = {}, -- nav area id -> its floor neighbours' ids (read again when seams are linked: WSNavLinked)
	centers = {}, -- nav area id -> its centre
	navBlocked = {}, -- nav area id -> the teams its doors and brushes block (games.nextsoldier.doors)
	nextBlockerRefresh = 0,
	blockerGeneration = 0,
	blockerLog = {}, -- the latest generations: { generation, changes = area id -> true, or nil when not known }
	-- reach = nil, -- the regions failed route searches walked (games.nextsoldier.reach_memo), set by sv_routes
	reachStats = { answered = 0, retargeted = 0, learned = 0 }, -- requests answered from them, searches sent to a region's nearest area, regions learned
	brushAreas = setmetatable({}, { __mode = "k" }), -- func_brush -> { pos, areas it stands in }
	-- doorAreas = nil, -- nav area id -> true under a func_door, set by RefreshBlockers
	-- doorStates = nil, -- func_door -> how the blockers see it, set by RefreshBlockers
	-- doorWalls = nil, -- nav area id -> true where a shut door no trigger opens stands, set by RefreshBlockers
	-- blockerSignature = nil, -- what the blockers blocked at the last refresh, set by RefreshBlockers
}

-- Parts ------------------------------------------------------------------------------

local Part = WS.FeatureParts(getfenv(1), "npc")
Part("sv_blockers", Controller)
local NavGraph = Part("sv_routes", Controller)
Part("sv_profile", Controller, NavGraph)

-- Bind, spawn, bosses -------------------------------------------------------------------

function Controller:CheckNavMesh()
	if self.navChecked then return end
	self.navChecked = true
	if not navmesh.IsLoaded() or navmesh.GetNavAreaCount() == 0 then
		print(string.format(NAV_MESSAGE, game.GetMap()))
	end
end

-- The NPCs bound to one variant, oldest first.
function Controller:NpcsOf(variantName)
	local found = {}
	for ent, name in pairs(self.variantNames) do
		if name == variantName then found[#found + 1] = ent end
	end
	table.sort(found, function(a, b) return a:GetCreationID() < b:GetCreationID() end)
	local npcs = {}
	for i, ent in ipairs(found) do npcs[i] = self.npcs[ent] end
	return npcs
end

-- The first NPC of a variant precaches the particle systems it may send
-- (their files are sh.lua's), so clients can look the names up; before it
-- binds, since its first action may send one.
function Controller:PrecacheParticles(variantName, variant)
	if self.precached[variantName] then return end
	self.precached[variantName] = true
	for _, name in ipairs(NpcSystem.Particles(variant)) do PrecacheParticleSystem(name) end
end

function Controller:Bind(ent, variantName, config)
	self:CheckNavMesh()
	local variant = WS.require(variantName)
	self:PrecacheParticles(variantName, variant)
	local npc = NpcSystem.Npc.New(variant, config, ent)
	self.npcs[ent] = npc
	self.variantNames[ent] = variantName
	self.kinds[variant.KIND] = self.kinds[variant.KIND] or {}
	self.kinds[variant.KIND][ent] = true
	NpcSystem.Cull(variant, self:NpcsOf(variantName))
	return npc
end

function Controller:Unbind(ent)
	local npc = self.npcs[ent]
	npc:Destroy()
	self.kinds[npc.variant.KIND][ent] = nil
	self.npcs[ent] = nil
	self.variantNames[ent] = nil
	local spawner = self.spawnedBy[ent]
	if spawner then
		spawner:Died(ent)
		self.spawnedBy[ent] = nil
	end
end

function Controller:All(kind)
	local found = {}
	for ent in pairs(self.kinds[kind] or {}) do found[#found + 1] = ent end
	return found
end

function Controller:Shared(variantName)
	self.shared[variantName] = self.shared[variantName] or {}
	return self.shared[variantName]
end

-- Every spawnable class of this gamemode takes its config through Configure.
function Controller:Spawn(class, config, pos, ang)
	local ent = ents.Create(class)
	ent:Configure(config)
	ent:SetPos(pos)
	ent:SetAngles(ang)
	ent:Spawn()
	return ent
end

-- A boss's convars (its variant's CONVARS: TF2's names and defaults), each
-- created as a cheat the first time it is asked for, and their values now.
function Controller:BossConvars(defaults)
	local values = {}
	for name, default in pairs(defaults) do
		local convar = GetConVar(name) or CreateConVar(name, tostring(default), FCVAR_CHEAT)
		values[name] = convar:GetFloat()
	end
	return values
end

function Controller:SetBossHealth(fraction)
	SetGlobal2Float(BOSS_HEALTH, fraction)
end

function Controller:BindSpawner(ent, config)
	local spawner = Spawner.New(config)
	self.spawners[ent] = spawner
	return spawner
end

-- Spawn at the spawner's origin whatever the models ask for. A spawner the
-- map removed is forgotten.
function Controller:ThinkSpawners(now)
	for ent, spawner in pairs(self.spawners) do
		if not IsValid(ent) then
			self.spawners[ent] = nil
		else
			local request = spawner:Think(now, math.Rand)
			if request then
				local npc = self:Spawn(request.class, request.config, ent:GetPos(), ent:GetAngles())
				spawner:Spawned(npc)
				self.spawnedBy[npc] = spawner
			end
		end
	end
end

-- The mesh's links changed: the neighbours read from it are read again, and
-- routes planned before are stale.
hook.Add("WSNavLinked", "ws_npc_blockers", function()
	Controller.neighbors = {}
	Controller:NoteBlockerChange(nil)
end)

-- The nbdebug feature finds the NPCs it can show through the hook
-- WSNbDebugNpcs(found): each system adds its entities' games.npc.nextbot
-- Npcs to `found` (entity -> Npc).
hook.Add("WSNbDebugNpcs", "ws_npc", function(found)
	for ent, npc in pairs(Controller.npcs) do
		if IsValid(ent) then found[ent] = npc end
	end
end)

hook.Add("Think", "ws_npc_spawners", function()
	Controller:ThinkSpawners(CurTime())
	Controller:ThinkSearches()
end)

-- The model's FilterDamage decides whether an NPC takes a hit, and how much.
hook.Add("EntityTakeDamage", "ws_npc_filter_damage", function(ent, dmg)
	local npc = Controller.npcs[ent]
	if not npc then return end
	local taken, amount = npc:FilterDamage(ent:DamageEvent(dmg))
	if not taken then return true end
	if amount then dmg:SetDamage(amount) end
end)

return Controller
