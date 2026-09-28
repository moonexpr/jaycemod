-- The npc feature's controller. It owns one foundation.npc Npc per NPC
-- entity, the foundation.npc.spawner models, a registry by kind and the
-- per-variant shared state, and checks the navigation mesh once per map.
-- The rules live in the models; this file only feeds them engine events and
-- turns their answers into entities.
local NpcSystem = WETSAND.require("foundation.npc")
local Spawner = WETSAND.require("foundation.npc.spawner")
local Profile = WETSAND.require("foundation.npc.profile")

local NAV_MESSAGE = "wetsand_nextbot: %s has no usable navigation mesh; run .devtools/bin/nav_convert.py or nav_generate"
local BOSS_HEALTH = "wetsand_boss_health" -- the boss bar's fraction; 0 hides it

local Controller = {
	npcs = {}, -- entity -> Npc
	variantNames = {}, -- entity -> variant name
	kinds = {}, -- kind -> { [entity] = true }
	shared = {}, -- variant name -> table
	spawners = {}, -- spawner entity -> Spawner
	spawnedBy = {}, -- NPC entity -> Spawner
	navChecked = false,
	pathProfile = nil, -- a foundation.npc.profile while wetsand_path_profile's window is open
}

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

function Controller:Bind(ent, variantName, config)
	self:CheckNavMesh()
	local variant = WETSAND.require(variantName)
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

-------------------------------------------------------------------------------
-- Path profiling: whether the NextBots' path search is worth moving off the
-- main thread (a binary module), measured before anything is built.

local PROFILE_WINDOW_DEFAULT, PROFILE_WINDOW_MAX = 30, 600
local BENCH_DEFAULT, BENCH_MAX = 200, 5000

function Controller:PathProfile()
	return self.pathProfile
end

-- Runs compute(), a Path:Compute through bot's cost function, and records
-- how long it took and how much of that was the cost callback.
function Controller:MeasureCompute(profile, label, bot, compute)
	local probe = { costCalls = 0, costSeconds = 0 }
	bot.pathProbe = probe
	local started = SysTime()
	local found = compute()
	local seconds = SysTime() - started
	bot.pathProbe = nil
	profile:Record({
		label = label,
		seconds = seconds,
		costCalls = probe.costCalls,
		costSeconds = probe.costSeconds,
		found = found,
	})
	return found
end

-- Every live NextBot of this gamemode that searches with a Lua cost.
local function PathingBots()
	local bots = {}
	for ent in pairs(Controller.npcs) do
		if IsValid(ent) and ent.pathCost then bots[#bots + 1] = ent end
	end
	table.sort(bots, function(a, b) return a:EntIndex() < b:EntIndex() end)
	return bots
end

-- One goal, computed with the engine's own cost and then with the bot's
-- Lua cost, on paths of their own so the bot's path is left alone.
function Controller:BenchGoal(profile, bot, goal)
	local enginePath = Path("Follow")
	self:MeasureCompute(profile, Profile.BENCH_ENGINE_LABEL, bot, function() return enginePath:Compute(bot, goal) end)
	local luaPath = Path("Follow")
	self:MeasureCompute(profile, bot.Variant, bot, function() return luaPath:Compute(bot, goal, bot.pathCost) end)
end

local function Tell(ply, lines)
	for _, line in ipairs(lines) do
		print(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	end
end

local function Admin(ply)
	return not IsValid(ply) or ply:IsAdmin()
end

concommand.Add("wetsand_path_profile", function(ply, _, args)
	if not Admin(ply) then return end
	if Controller.pathProfile then
		Tell(ply, { "path profile: a window is already open" })
		return
	end
	local seconds = math.Clamp(tonumber(args[1]) or PROFILE_WINDOW_DEFAULT, 1, PROFILE_WINDOW_MAX)
	Controller.pathProfile = Profile.New(SysTime())
	Tell(ply, { string.format("path profile: measuring every path compute for %d s", seconds) })
	timer.Simple(seconds, function()
		local profile = Controller.pathProfile
		Controller.pathProfile = nil
		Tell(ply, Profile.Format(profile:Report(SysTime()), engine.TickInterval()))
	end)
end, nil, "Measure the NextBots' path computes during play for N seconds (default 30) and print whether offloading them would pay")

-- The bench stalls the server for its whole run, on purpose.
concommand.Add("wetsand_path_bench", function(ply, _, args)
	if not Admin(ply) then return end
	local bots, areas = PathingBots(), navmesh.GetAllNavAreas()
	if #bots == 0 then
		Tell(ply, { "path bench: no NextBot with a path cost is alive; spawn one first" })
		return
	end
	if #areas == 0 then
		Tell(ply, { "path bench: this map has no navigation mesh" })
		return
	end
	local count = math.Clamp(tonumber(args[1]) or BENCH_DEFAULT, 1, BENCH_MAX)
	local profile = Profile.New(SysTime(), true)
	for i = 1, count do
		local bot = bots[(i - 1) % #bots + 1]
		Controller:BenchGoal(profile, bot, areas[math.random(#areas)]:GetCenter())
	end
	Tell(ply, Profile.Format(profile:Report(SysTime()), engine.TickInterval()))
end, nil, "Compute N paths (default 200) from the live NextBots to random nav areas, under the engine's cost and their Lua cost, and print the timings")

hook.Add("Think", "wetsand_npc_spawners", function()
	Controller:ThinkSpawners(CurTime())
end)

-- The model's FilterDamage decides what an NPC takes.
hook.Add("EntityTakeDamage", "wetsand_npc_filter_damage", function(ent, dmg)
	local npc = Controller.npcs[ent]
	if npc and not npc:FilterDamage(ent:DamageEvent(dmg)) then return true end
end)

return Controller
