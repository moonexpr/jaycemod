local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local Spawner = T.require("foundation.npc.spawner")

local SPAWNER_TEAM, NPC_TEAM = 0, 5 -- arbitrary team numbers: the model only passes them through

local function New(overrides, random)
	local cfg = {
		class = "probe_npc",
		team = SPAWNER_TEAM,
		maxActive = 3,
		infinite = false,
		npcConfig = {
			lifetime = 240,
			kind = "normal",
		},
		teamOf = function(team)
			T.eq(team, SPAWNER_TEAM, "teamOf gets the spawner's team")
			return NPC_TEAM
		end,
	}
	for k, v in pairs(overrides or {}) do cfg[k] = v end
	return Spawner.New(cfg)
end

-- Drives a spawner the way the controller does: think whenever it is due,
-- and report each spawn back. Returns the times it spawned.
local function Run(spawner, clock, random, untilTime, spawned)
	local times = {}
	local due = clock:Now()
	while clock:Now() <= untilTime do
		if clock:Now() >= due then
			local request, nextThink = spawner:Think(clock:Now(), function(lo, hi) return random:Float(lo, hi) end)
			if request then
				local handle = { n = #spawned + 1 }
				spawned[#spawned + 1] = handle
				spawner:Spawned(handle)
				times[#times + 1] = clock:Now()
			end
			due = nextThink
		end
		clock:Advance(0.05)
	end
	return times
end

T.test("an idle spawner thinks every IDLE_THINK and requests nothing", function()
	local s = New()
	local request, nextThink = s:Think(10, function() error("no draw while idle") end)
	T.eq(request, nil, "disabled")
	T.near(nextThink, 10 + Spawner.IDLE_THINK, 1e-9, "next think")
	T.defined(Spawner.IDLE_THINK, "Spawner.IDLE_THINK")
	request, nextThink = s:Think(10 + Spawner.IDLE_THINK / 2, function() error("not due") end)
	T.eq(request, nil, "not due yet")
	T.near(nextThink, 10 + Spawner.IDLE_THINK, 1e-9, "still due at the first think")
end)

T.test("a request carries the class and the configured NPC with the team strategy's team", function()
	local s = New()
	s:Enable(5)
	local request = s:Think(5, function(lo, hi) return lo end)
	T.eq(request.class, "probe_npc", "class")
	T.eq(request.config.team, NPC_TEAM, "team")
	T.eq(request.config.lifetime, 240, "lifetime")
	T.eq(request.config.kind, "normal", "kind")
	local again = s:Think(10, function(lo, hi) return lo end)
	T.eq(again.config == request.config, false, "each request has its own config")
end)

T.test("scenario: a finite spawner spawns up to its cap at 1.5-3 s intervals, and deaths do not refill it", function()
	local clock = Fake.Clock(1)
	local random = Fake.Random({ 0, 1, 0.5 })
	local s = New()
	local spawned = {}
	Run(s, clock, random, 2, spawned)
	T.eq(#spawned, 0, "nothing before Enable")
	s:Enable(clock:Now())
	local start = clock:Now()
	local times = Run(s, clock, random, start + 20, spawned)
	T.eq(#times, 3, "three spawns")
	T.near(times[1], start, 1e-6, "the first at once")
	T.near(times[2] - times[1], 1.5, 0.051, "then after 1.5 s")
	T.near(times[3] - times[2], 3, 0.051, "then after 3 s")
	s:Died(spawned[1])
	s:Died(spawned[2])
	times = Run(s, clock, random, clock:Now() + 20, spawned)
	T.eq(#times, 0, "a finite spawner counts spawns, not the living")
end)

T.test("scenario: an infinite spawner refills when its NPCs die", function()
	local clock = Fake.Clock(1)
	local random = Fake.Random({ 0 })
	local s = New({
		infinite = true,
		maxActive = 2,
	})
	local spawned = {}
	s:Enable(clock:Now())
	local times = Run(s, clock, random, clock:Now() + 10, spawned)
	T.eq(#times, 2, "two alive at the cap")
	s:Died(spawned[1])
	times = Run(s, clock, random, clock:Now() + 10, spawned)
	T.eq(#times, 1, "one replacement")
	T.eq(#spawned, 3, "three in all")
end)

T.test("scenario: Disable stops it and resets the count, so Enable spawns a full set again", function()
	local clock = Fake.Clock(1)
	local random = Fake.Random({ 0 })
	local s = New({ maxActive = 2 })
	local spawned = {}
	s:Enable(clock:Now())
	Run(s, clock, random, clock:Now() + 10, spawned)
	T.eq(#spawned, 2, "full")
	s:Disable()
	local times = Run(s, clock, random, clock:Now() + 10, spawned)
	T.eq(#times, 0, "disabled")
	s:Enable(clock:Now())
	times = Run(s, clock, random, clock:Now() + 10, spawned)
	T.eq(#times, 2, "a full set again, the old NPCs forgotten")
end)

T.test("SetMaxActive raises the cap of a running spawner", function()
	local clock = Fake.Clock(1)
	local random = Fake.Random({ 0 })
	local s = New({ maxActive = 1 })
	local spawned = {}
	s:Enable(clock:Now())
	Run(s, clock, random, clock:Now() + 10, spawned)
	T.eq(#spawned, 1, "one")
	s:SetMaxActive(3)
	Run(s, clock, random, clock:Now() + 10, spawned)
	T.eq(#spawned, 3, "three")
end)

T.test("Enable makes a waiting spawner think at once", function()
	local s = New()
	local _, nextThink = s:Think(10, function() return 0 end)
	T.near(nextThink, 10 + Spawner.IDLE_THINK, 1e-9, "idle")
	local soon = 10 + Spawner.IDLE_THINK / 4
	s:Enable(soon)
	local request = s:Think(soon, function(lo) return lo end)
	T.eq(request ~= nil, true, "spawns at once")
end)

T.finish()
