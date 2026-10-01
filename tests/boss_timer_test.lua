local T = dofile("tests/harness.lua")
local FakeActor = dofile("tests/fake_actor.lua")
local BossTimer = T.require("foundation.npc.boss_timer")
local Merasmus = T.require("foundation.npc.merasmus")
local HalloweenBoss = T.require("foundation.npc.halloween_boss")
local Teams = T.require("foundation.teams")

local V = FakeActor.Vector
local MIDDLE = 0.5 -- a random draw half way: the interval itself
local EARLIEST = 0 -- a random draw at the bottom: interval - variation

-- The gamerules' side of the timer, as the boss timer controller gives it.
local function World(t)
	t = t or {}
	local world = {
		clock = FakeActor.Clock(t.now or 100),
		random = FakeActor.Random(t.random or { MIDDLE }),
		halloween = t.halloween ~= false,
		bossActive = t.bossActive or false,
		level = t.level or Merasmus.FIRST_LEVEL,
		convars = t.convars or Merasmus.CONVARS,
		setup = t.setup or false,
		waiting = t.waiting or false,
		humans = t.humans or Merasmus.CONVARS.tf_halloween_bot_min_player_count,
		customSpawn = t.customSpawn,
		points = t.points or {},
		areas = t.areas or {},
		areaSizes = {},
	}
	function world:Now() return self.clock:Now() end
	function world:RandomFloat(lo, hi) return self.random:Float(lo, hi) end
	function world:RandomInt(lo, hi) return self.random:Int(lo, hi) end
	function world:Vector(x, y, z) return V(x, y, z) end
	function world:HalloweenActive() return self.halloween end
	function world:BossActive() return self.bossActive end
	function world:Level() return self.level end
	function world:Convars() return self.convars end
	function world:InSetup() return self.setup end
	function world:WaitingForPlayers() return self.waiting end
	function world:LivingHumans() return self.humans end
	function world:CustomSpawn() return self.customSpawn end
	function world:ControlPoints() return self.points end
	function world:SpawnAreas(minSize)
		self.areaSizes[#self.areaSizes + 1] = minSize
		return self.areas
	end
	return world
end

local function Advance(world, seconds) world.clock:Advance(seconds) end

-- RED holds the first point, which BLU may take; the second is locked.
local function Points()
	return {
		{
			origin = V(100, 0, 0),
			inRound = true,
			owner = Teams.RED,
			blueMayCapture = true,
		},
		{
			origin = V(200, 0, 0),
			inRound = true,
			owner = Teams.RED,
			blueMayCapture = false,
		},
	}
end

-- A timer whose countdown has run out, with no boss about.
local function Elapsed(world)
	local timer = BossTimer.New(Merasmus)
	timer:Start(Merasmus.CONVARS.tf_merasmus_spawn_interval, 0, world)
	Advance(world, Merasmus.CONVARS.tf_merasmus_spawn_interval + 1)
	return timer
end

-------------------------------------------------------------------------------
-- The intervals (CTFGameRules::SpawnHalloweenBoss, CMerasmus::StartRespawnTimer)

T.test("Merasmus comes back every 180 s, give or take 30, and every minute past the third level", function()
	local cv = Merasmus.CONVARS
	T.eq(cv.tf_merasmus_spawn_interval, 180, "tf_merasmus_spawn_interval")
	T.eq(cv.tf_merasmus_spawn_interval_variation, 30, "tf_merasmus_spawn_interval_variation")
	T.eq(cv.tf_halloween_bot_min_player_count, 10, "tf_halloween_bot_min_player_count")
	local seconds, variation = Merasmus.SpawnInterval(3, cv)
	T.eq(seconds, 180, "third level")
	T.eq(variation, 30, "varies")
	seconds, variation = Merasmus.SpawnInterval(4, cv)
	T.eq(seconds, 60, "fourth level")
	T.eq(variation, 0, "exactly")
	T.eq(Merasmus.NEUTRALIZES_POINT, true, "his spawn reverts the point he takes")
end)

T.test("a start draws its length between interval - variation and interval + variation", function()
	local world = World({ random = { EARLIEST } })
	local timer = BossTimer.New(Merasmus)
	timer:Start(180, 30, world)
	T.near(timer:Remaining(world), 150, 1e-9, "the earliest")
	world.random = FakeActor.Random({ 1 })
	timer:Start(180, 30, world)
	T.near(timer:Remaining(world), 210, 1e-9, "the latest")
end)

-------------------------------------------------------------------------------
-- SpawnHalloweenBoss

T.test("outside Halloween the timer does nothing", function()
	local world = World({ halloween = false })
	local timer = BossTimer.New(Merasmus)
	T.eq(timer:Update(world), nil, "no spawn")
	T.eq(timer:HasStarted(), false, "not started")
end)

T.test("never started, it starts with his interval and spawns nothing yet", function()
	local world = World({ points = Points() })
	local timer = BossTimer.New(Merasmus)
	T.eq(timer:Update(world), nil, "no spawn")
	T.eq(timer:HasStarted(), true, "started")
	T.near(timer:Remaining(world), 180, 1e-9, "the interval")
end)

T.test("while any Halloween boss is about, the timer starts over every update", function()
	local world = World({
		points = Points(),
		bossActive = true,
	})
	local timer = Elapsed(world)
	T.eq(timer:Update(world), nil, "no second boss")
	T.near(timer:Remaining(world), 180, 1e-9, "restarted")
	Advance(world, 100)
	timer:Update(world)
	T.near(timer:Remaining(world), 180, 1e-9, "restarted again")
end)

T.test("before the countdown ends nothing spawns", function()
	local world = World({ points = Points() })
	local timer = BossTimer.New(Merasmus)
	timer:Start(180, 0, world)
	Advance(world, 179)
	T.eq(timer:Update(world), nil, "not yet")
end)

T.test("when it ends he spawns at the point BLU must take next, which goes neutral", function()
	local world = World({ points = Points() })
	local timer = Elapsed(world)
	local spawn = timer:Update(world)
	local class, config, pos = HalloweenBoss.SpawnAt(HalloweenBoss.BOSS_MERASMUS, V(100, 0, 0), Teams.HALLOWEEN, nil, V)
	T.eq(spawn.class, class, "merasmus")
	T.eq(spawn.config.team, config.team, "on the Halloween team")
	T.eq(spawn.config.owner, nil, "nobody's")
	T.eq(spawn.pos, pos, "10 above the point")
	T.eq(spawn.neutralize, world.points[1], "the point reverts to neutral")
	T.near(timer:Remaining(world), 180, 1e-9, "the next one is timed")
end)

T.test("the contested point skips BLU's and those BLU may not take; with none, the last", function()
	local world = World({ points = Points() })
	world.points[1].owner = Teams.BLUE
	world.points[2].blueMayCapture = true
	local spawn = Elapsed(world):Update(world)
	T.eq(spawn.neutralize, world.points[2], "BLU's own is skipped")
	world = World({ points = Points() })
	world.points[1].blueMayCapture = false
	spawn = Elapsed(world):Update(world)
	T.eq(spawn.neutralize, world.points[2], "the loop ends on the last")
	world = World({ points = Points() })
	world.points[1].inRound = false
	world.points[2].blueMayCapture = true
	spawn = Elapsed(world):Update(world)
	T.eq(spawn.neutralize, world.points[2], "a point out of the round is passed over")
end)

T.test("a spawn_boss entity wins over the point, which keeps its owner", function()
	local world = World({
		points = Points(),
		customSpawn = V(0, 500, 0),
	})
	local spawn = Elapsed(world):Update(world)
	T.eq(spawn.pos, V(0, 500, HalloweenBoss.SPAWN_HEIGHT), "at spawn_boss")
	T.eq(spawn.neutralize, nil, "no point touched")
end)

T.test("with no points he spawns at a random big nav area outside the spawn rooms", function()
	local world = World({
		areas = { V(0, 0, 0), V(1000, 0, 0) },
		random = { MIDDLE, 1 },
	})
	local timer = BossTimer.New(Merasmus)
	timer:Start(180, 30, world)
	Advance(world, 181)
	local spawn = timer:Update(world)
	T.eq(world.areaSizes[1], BossTimer.SPAWN_AREA_SIZE, "areas at least 100 a side")
	T.eq(spawn.pos, V(1000, 0, HalloweenBoss.SPAWN_HEIGHT), "the drawn area")
	T.eq(spawn.neutralize, nil, "no point")
end)

T.test("with no place to spawn, nothing happens and the timer stays run out", function()
	local world = World()
	local timer = Elapsed(world)
	T.eq(timer:Update(world), nil, "nowhere")
	T.eq(timer:Remaining(world) < 0, true, "still elapsed")
end)

T.test("he waits out setup, waiting for players and too few living humans", function()
	local world = World({
		points = Points(),
		setup = true,
	})
	local timer = Elapsed(world)
	T.eq(timer:Update(world), nil, "setup")
	world.setup = false
	world.waiting = true
	T.eq(timer:Update(world), nil, "waiting for players")
	world.waiting = false
	world.humans = Merasmus.CONVARS.tf_halloween_bot_min_player_count - 1
	T.eq(timer:Update(world), nil, "nine humans")
	world.humans = world.humans + 1
	T.eq(timer:Update(world) ~= nil, true, "ten")
end)

T.test("past the third level the next one comes a minute later", function()
	local world = World({
		points = Points(),
		level = 4,
	})
	local spawn = Elapsed(world)
	spawn:Update(world)
	T.near(spawn:Remaining(world), 60, 1e-9, "a minute")
end)

-------------------------------------------------------------------------------
-- tf_halloween_force_boss_spawn, and the round's start

T.test("a forced spawn skips the countdown and the player checks, once", function()
	local world = World({
		points = Points(),
		setup = true,
		humans = 0,
	})
	local timer = BossTimer.New(Merasmus)
	timer:Start(180, 0, world)
	timer:Force()
	T.eq(timer:Update(world) ~= nil, true, "spawned at once")
	T.eq(timer:Update(world), nil, "just the once")
end)

T.test("a forced spawn while a boss is about is dropped", function()
	local world = World({
		points = Points(),
		bossActive = true,
	})
	local timer = BossTimer.New(Merasmus)
	timer:Force()
	T.eq(timer:Update(world), nil, "not while one is out")
	world.bossActive = false
	T.eq(timer:Update(world), nil, "and forgotten")
end)

T.test("a new round forgets the countdown, which starts over", function()
	local world = World({ points = Points() })
	local timer = Elapsed(world)
	timer:Invalidate()
	T.eq(timer:HasStarted(), false, "forgotten")
	T.eq(timer:Update(world), nil, "no spawn on the round's first update")
	T.near(timer:Remaining(world), 180, 1e-9, "a fresh interval")
end)

T.finish()
