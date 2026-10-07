-- The boss_timer feature's controller: TF2's Halloween boss timer
-- (foundation.npc.boss_timer) for each boss the map has brought in. It
-- implements the timer's world port, runs SpawnHalloweenBoss every tick,
-- spawns what the timer asks for, reverts the point the boss takes and
-- pauses the KOTH clocks, and forgets the countdown when a round starts.
--
-- Loaded by the first boss that brings the timer (merasmus). A boss variant
-- run here provides what foundation.npc.boss_timer asks of it, plus
-- SharedLevel(shared) -> its level from the npc controller's shared table.
local BossTimer = WETSAND.require("foundation.npc.boss_timer")
local Holiday = WETSAND.require("foundation.holiday")
local HalloweenBoss = WETSAND.require("foundation.npc.halloween_boss")

local THINK_HOOK = "wetsand_boss_timer"
local CUSTOM_SPAWN_CLASS = "spawn_boss" -- SpawnHalloweenBoss looks it up by class
local MASTER_CLASS = "team_control_point_master"
local WHEEL_CLASS = "wheel_of_doom"
local MERASMUS = "foundation.npc.merasmus"
local GAME_TEAMS = { WETSAND.TEAM_RED, WETSAND.TEAM_BLUE }

local Controller = {
	npcs = WETSAND.Feature("npc"),
	runs = {}, -- variant name -> { timer, world }
}

local function LivingHumans()
	local count = 0
	for _, t in ipairs(GAME_TEAMS) do
		for _, ply in ipairs(team.GetPlayers(t)) do
			if ply:Alive() and not ply:IsBot() then count = count + 1 end
		end
	end
	return count
end

-- The master's points in order, as the Horsemann's, with their entities.
local function ControlPoints()
	local points = {}
	if not IsValid(ents.FindByClass(MASTER_CLASS)[1]) then return points end
	local capture = WETSAND.Feature("capture")
	for i, point in ipairs(capture:Points()) do
		points[i] = {
			entity = point,
			origin = point:GetPos(),
			inRound = capture:IsInRound(point),
			owner = capture:Owner(point),
			blueMayCapture = capture:TeamMayCapture(point, WETSAND.TEAM_BLUE),
		}
	end
	return points
end

-- The nav areas at least minSize a side outside the spawn rooms (TF2 also
-- skips spawn-room exits, which GMod's areas do not mark).
local function SpawnAreas(npcs, minSize)
	local centers = {}
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		if area:GetSizeX() >= minSize and area:GetSizeY() >= minSize and npcs:SpawnRoomTeam(area) == WETSAND.TEAM_UNASSIGNED then
			centers[#centers + 1] = area:GetCenter()
		end
	end
	return centers
end

-- The timer's world port for one boss variant.
local function World(npcs, variantName, variant)
	local world = {}
	function world:Now() return CurTime() end
	function world:RandomFloat(lo, hi) return math.Rand(lo, hi) end
	function world:RandomInt(lo, hi) return math.random(lo, hi) end
	function world:Vector(x, y, z) return Vector(x, y, z) end
	function world:HalloweenActive() return WETSAND.Feature("holiday"):HolidayActive(Holiday.HALLOWEEN) end
	function world:BossActive() return #npcs:All(HalloweenBoss.KIND) > 0 end
	function world:Level() return variant.SharedLevel(npcs:Shared(variantName)) end
	function world:Convars() return npcs:BossConvars(variant.CONVARS) end
	function world:InSetup() return WETSAND.InSetup() end
	function world:WaitingForPlayers() return WETSAND.State() == WETSAND.STATE.PREGAME end
	function world:LivingHumans() return LivingHumans() end

	function world:CustomSpawn()
		local spot = ents.FindByClass(CUSTOM_SPAWN_CLASS)[1]
		return IsValid(spot) and spot:GetPos() or nil
	end

	function world:ControlPoints() return ControlPoints() end
	function world:SpawnAreas(minSize) return SpawnAreas(npcs, minSize) end

	-- The first wheel_of_doom, which loaded the wheel feature as it bound.
	function world:WheelBusy()
		local wheel = ents.FindByClass(WHEEL_CLASS)[1]
		return IsValid(wheel) and WETSAND.Feature("wheel"):Busy(wheel)
	end
	return world
end

-- A map's boss brings its timer; once is enough.
function Controller:Run(variantName)
	if self.runs[variantName] then return end
	local variant = WETSAND.require(variantName)
	self.runs[variantName] = {
		timer = BossTimer.New(variant),
		world = World(self.npcs, variantName, variant),
	}
end

-- TFGameRules()->StartHalloweenBossTimer
function Controller:Start(variantName, seconds, variation)
	self:Run(variantName)
	local run = self.runs[variantName]
	run.timer:Start(seconds, variation, run.world)
end

-- The spawn: the boss, then the point it takes goes neutral and the KOTH
-- clocks stop.
function Controller:Apply(spawn)
	self.npcs:Spawn(spawn.class, spawn.config, spawn.pos, angle_zero)
	if not spawn.neutralize then return end
	WETSAND.Feature("capture"):ForceOwner(spawn.neutralize.entity, WETSAND.TEAM_UNASSIGNED)
	local rounds = WETSAND.Feature("rounds")
	for _, t in ipairs(GAME_TEAMS) do
		local clock = rounds:TeamClock(t)
		if clock then rounds:TimerInput(clock, "pause") end
	end
end

function Controller:Think()
	for _, run in pairs(self.runs) do
		local spawn = run.timer:Update(run.world)
		if spawn then self:Apply(spawn) end
	end
end

hook.Add("Think", THINK_HOOK, function() Controller:Think() end)

-- CTFGameRules::SetupOnRoundStart
hook.Add("WetsandRoundSpawn", THINK_HOOK, function()
	for _, run in pairs(Controller.runs) do run.timer:Invalidate() end
end)

local function ForceAll()
	for _, run in pairs(Controller.runs) do run.timer:Force() end
end

-- TF2's cheat commands (tf_gamerules.cpp); the engine refuses them without
-- sv_cheats.
concommand.Add("tf_halloween_force_boss_spawn", ForceAll, nil, "For testing.", FCVAR_CHEAT)

concommand.Add("cc_spawn_merasmus_at_level", function(_, _, args)
	local level = tonumber(args[1])
	if not level then
		print("Must specify a level")
		return
	end
	Controller.npcs:Shared(MERASMUS).level = math.floor(level)
	ForceAll()
end, nil, "Force Merasmus to spawn at a specific difficulty level", FCVAR_CHEAT)

return Controller
