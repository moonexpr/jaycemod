-- The Halloween boss timer, as CTFGameRules runs it (m_halloweenBossTimer,
-- StartHalloweenBossTimer and SpawnHalloweenBoss, tf_gamerules.cpp): while a
-- Halloween boss is about the countdown keeps starting over; once it runs
-- out (or tf_halloween_force_boss_spawn asks) the boss spawns on the point
-- BLU must take next, and the next countdown begins. A new round forgets it
-- (SetupOnRoundStart), and the first update after starts it afresh.
--
-- TF2 runs it on the map whose Halloween scenario names the boss (Merasmus:
-- koth_lakeside_event, by its name). Sandcastle names no maps; it reads the
-- scenario from what the map places (SCENARIOS, Runs): the relay the boss
-- triggers as he arrives, with no boss of the map's own. A map built for
-- the game to bring him (lakeside) has both; maps whose own logic spawns him
-- (pl_fifthcurve_event, pl_rumble_event, koth_slasher) place him and no
-- relay; koth_moonshine_event has his wheel but no relay, and TF2 brings
-- no Merasmus there either. A boss the map's logic spawns anyway stops the
-- timer for good (MapSpawned).
--
-- New(boss) takes a foundation.npc.halloween_boss part that provides
-- BOSS_TYPE, SpawnInterval(level, convars) -> seconds, variation (the
-- scenario's intervals), and optionally NEUTRALIZES_POINT (VIADUCT and
-- LAKESIDE revert the point the boss takes) and WAITS_FOR_WHEEL (LAKESIDE
-- does nothing while the first wheel_of_doom is busy). Its world port:
--   Now(), RandomFloat(lo, hi), RandomInt(lo, hi), Vector(x, y, z);
--   HalloweenActive(), BossActive() (any Halloween boss alive),
--   Level() (the boss's shared level), Convars() (the boss's convars now,
--   with tf_halloween_bot_min_player_count);
--   InSetup(), WaitingForPlayers(), LivingHumans() (RED and BLU, no bots);
--   CustomSpawn() -> a spawn_boss's origin | nil;
--   ControlPoints() -> the master's points in order, each { origin,
--     inRound, owner, blueMayCapture } (as the Horsemann's);
--   SpawnAreas(minSize) -> the centres of the nav areas outside the spawn
--     rooms at least minSize on each side;
--   WheelBusy() -> whether the first wheel_of_doom is still spinning or
--     naming its effect (not IsDoneBoardcastingEffectSound).
local require = require
local HalloweenBoss = require("foundation.npc.halloween_boss")
local Teams = require("foundation.teams")
local setmetatable, ipairs = setmetatable, ipairs
module(...)

SPAWN_AREA_SIZE = 100 -- SpawnHalloweenBoss's goodSize
local UNSTARTED = -1

-- The bosses' scenarios: the boss variant, the class a map would place him
-- as, and the relay he triggers as he arrives (CMerasmus::Spawn's
-- TriggerLogicRelay; only Merasmus triggers one).
SCENARIOS = {
	{
		variant = "foundation.npc.merasmus",
		bossClass = "merasmus",
		arrivalRelay = "boss_enter_relay",
	},
}

-- Whether the timer runs for the scenario on a map that places these:
-- map = { names = set of targetnames, classes = set of classnames }.
function Runs(scenario, map)
	return map.names[scenario.arrivalRelay] == true and not map.classes[scenario.bossClass]
end

local Timer = {}
Timer.__index = Timer

function New(boss)
	return setmetatable({
		boss = boss,
		timestamp = UNSTARTED,
		forcing = false,
		mapSpawns = false,
	}, Timer)
end

-- StartHalloweenBossTimer
function Timer:Start(seconds, variation, world)
	if self.mapSpawns then return end
	self.timestamp = world:Now() + world:RandomFloat(seconds - variation, seconds + variation)
end

-- The map's own logic spawned the boss: the map is not his scenario.
function Timer:MapSpawned()
	self.mapSpawns = true
	self.timestamp = UNSTARTED
	self.forcing = false
end

function Timer:Invalidate() self.timestamp = UNSTARTED end
function Timer:HasStarted() return self.timestamp > 0 end
function Timer:Remaining(world) return self.timestamp - world:Now() end

-- tf_halloween_force_boss_spawn
function Timer:Force()
	if not self.mapSpawns then self.forcing = true end
end

local function IsElapsed(self, world) return world:Now() > self.timestamp end

local function Restart(self, world)
	local seconds, variation = self.boss.SpawnInterval(world:Level(), world:Convars())
	self:Start(seconds, variation, world)
end

-- The first point of the round BLU does not own and may capture; the loop
-- ends on the last point when none is.
local function ContestedPoint(points)
	local contested = nil
	for _, point in ipairs(points) do
		contested = point
		if point.inRound and point.owner ~= Teams.BLUE and point.blueMayCapture then break end
	end
	return contested
end

-- Where the boss spawns, the point it takes (or nil), or nothing at all.
local function SpawnPlace(self, world)
	local custom = world:CustomSpawn()
	if custom then return custom, nil end
	local point = ContestedPoint(world:ControlPoints())
	if point then return point.origin, self.boss.NEUTRALIZES_POINT and point or nil end
	local areas = world:SpawnAreas(SPAWN_AREA_SIZE)
	if #areas == 0 then return nil, nil end
	return areas[world:RandomInt(1, #areas)], nil
end

-- The spawn the countdown asks for, { class, config, pos, neutralize (the
-- point to revert, or nil) }, or nil. The config says timerSpawned, so the
-- boss is not taken for the map's own.
function Timer:Update(world)
	if self.mapSpawns or not world:HalloweenActive() then return nil end
	if self.boss.WAITS_FOR_WHEEL and world:WheelBusy() then return nil end
	if world:BossActive() then
		Restart(self, world)
		self.forcing = false
		return nil
	end
	if not IsElapsed(self, world) and not self.forcing then return nil end
	if not (self:HasStarted() or self.forcing) then
		Restart(self, world)
		return nil
	end
	if not self.forcing then
		if world:InSetup() or world:WaitingForPlayers() then return nil end
		if world:LivingHumans() < world:Convars().tf_halloween_bot_min_player_count then return nil end
	end
	local pos, neutralize = SpawnPlace(self, world)
	if pos == nil then return nil end
	local class, config, at = HalloweenBoss.SpawnAt(self.boss.BOSS_TYPE, pos, Teams.HALLOWEEN, nil, function(x, y, z)
		return world:Vector(x, y, z)
	end)
	config.timerSpawned = true
	Restart(self, world)
	self.forcing = false
	return {
		class = class,
		config = config,
		pos = at,
		neutralize = neutralize,
	}
end
