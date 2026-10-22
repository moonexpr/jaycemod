local T = dofile("tests/harness.lua")
local FakeActor = dofile("tests/fake_actor.lua")
local FakeCombatant = dofile("tests/fake_combatant.lua")
local NpcSystem = T.require("games.npc.nextbot")
local Ghost = T.require("foundation.npc.ghost")
local Players = T.require("games.gameplay.players")
local Teams = T.require("games.gameplay.teams")

local V = FakeCombatant.Vector
local TICK = 0.1
local EPSILON = 1e-6
local LIFETIME = 20

-- A ghost facing +x at the origin. walls(from, to) -> the feeler's hit
-- fraction, or nil when clear.
local function Scene(t)
	t = t or {}
	local world = FakeCombatant.World()
	local players = {}
	for i, p in ipairs(t.players or {}) do players[i] = world:AddPlayer(p) end
	local me = FakeCombatant.Combatant({
		world = world,
		variant = Ghost,
		origin = t.origin or V(0, 0, 0),
		random = t.random,
	})
	me.walls = t.walls or function() return nil end
	function me:FeelerHit(from, to) return self.walls(from, to) end
	local npc = NpcSystem.Npc.New(Ghost, { lifetime = t.lifetime or LIFETIME }, me)
	return {
		world = world,
		players = players,
		me = me,
		npc = npc,
	}
end

local function Tick(s, seconds)
	for _ = 1, math.max(1, math.floor(seconds / TICK + 0.5)) do
		s.me.clock:Advance(TICK)
		s.npc:Update(TICK)
	end
end

local function Called(me, name) return me:Called(name) end

-- The first tick starts the behavior; the second runs it.
local function Started(s) Tick(s, 2 * TICK) end

-- Keep the ghost moving, so it is never stuck: half way to its goal each
-- tick, or (pacing) back and forth 60 units, staying put.
local function Drifting(s, pacing)
	local approach = s.me.Approach
	function s.me:Approach(v)
		approach(self, v)
		if pacing then
			self.origin = self.origin.x == 0 and V(60, 0, 0) or V(0, 0, 0)
		else
			self.origin = self.origin + (v - self.origin) * 0.5
		end
	end
end

-------------------------------------------------------------------------------
-- CGhost

T.test("a ghost keeps TF2's numbers", function()
	T.eq(Ghost.MODEL, "models/props_halloween/ghost_no_hat.mdl", "its model")
	T.eq(Ghost.LOCOMOTION.runSpeed, 90, "GHOST_SPEED")
	T.eq(Ghost.LOCOMOTION.acceleration, 500, "acceleration")
	T.defined(Ghost.SCARE_RADIUS, "GHOST_SCARE_RADIUS")
	T.eq(Ghost.KIND, "ghost", "its kind")
end)

T.test("it appears in a puff, moans now and every 5-7 s, and drifts ahead", function()
	local s = Scene()
	Drifting(s)
	Started(s)
	T.eq(Called(s.me, "DispatchParticleEffect")[1][1], "ghost_appearation", "the puff")
	T.eq(Called(s.me, "EmitSound")[1][1], "Halloween.GhostMoan", "a moan")
	local approach = Called(s.me, "Approach")[1][1]
	T.near(approach.x, 100, EPSILON, "100 ahead")
	T.near(approach.y, 0, EPSILON, "straight")
	Tick(s, 4.8)
	T.eq(#Called(s.me, "EmitSound"), 1, "not again before 5 s")
	Tick(s, 2.2)
	T.eq(#Called(s.me, "EmitSound"), 2, "again by 7 s")
end)

T.test("a wall to one side turns it the other way", function()
	local s = Scene({
		walls = function(from, to)
			if to.y > from.y then return 0.5 end -- something to the left
			return nil
		end,
	})
	Drifting(s)
	Started(s)
	local approach = Called(s.me, "Approach")[1][1]
	T.eq(approach.y < 0, true, "turns right")
end)

T.test("walls both sides: it turns from the nearer", function()
	local s = Scene({
		walls = function(from, to)
			if to.y > from.y then return 0.3 end
			return 0.6
		end,
	})
	Drifting(s)
	Started(s)
	T.eq(Called(s.me, "Approach")[1][1].y < 0, true, "the left is nearer: right")
end)

T.test("it scares every living player near and in sight, once a second, unless in purgatory", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(Ghost.SCARE_RADIUS / 2, 0, 0),
				visible = true,
			},
			{
				team = Teams.BLUE,
				origin = V(Ghost.SCARE_RADIUS + 100, 0, 0),
				visible = true,
			},
			{
				team = Teams.BLUE,
				origin = V(0, Ghost.SCARE_RADIUS / 2, 0),
				visible = false,
			},
			{
				team = Teams.RED,
				origin = V(0, -Ghost.SCARE_RADIUS / 2, 0),
				visible = true,
				conds = { Players.COND.PURGATORY },
			},
		},
	})
	Drifting(s, true)
	Started(s)
	local stuns = Called(s.me, "StunPlayer")
	T.eq(#stuns, 1, "only the near one in sight")
	T.eq(stuns[1][1], s.players[1], "red")
	T.eq(stuns[1][2], Ghost.SCARE_TIME, "2 s")
	T.eq(stuns[1][3], 0, "no slow")
	T.eq(stuns[1][4], Players.STUN.LOSER_STATE + Players.STUN.BY_TRIGGER, "yikes")
	Tick(s, 0.5)
	T.eq(#Called(s.me, "StunPlayer"), 1, "not again within the second")
	Tick(s, 0.6)
	T.eq(#Called(s.me, "StunPlayer"), 2, "again")
end)

T.test("its time up, or stuck a second, it vanishes with a cry", function()
	local s = Scene({ lifetime = 3 })
	Drifting(s)
	Tick(s, 3.2)
	T.eq(s.me.removed, true, "gone after its lifetime")
	local sounds = Called(s.me, "EmitSound")
	T.eq(sounds[#sounds][1], "Halloween.Haunted", "the cry")
	local stuck = Scene()
	Tick(stuck, 1.2)
	T.eq(stuck.me.removed, true, "stuck: gone after a second")
end)

-------------------------------------------------------------------------------
-- CTFGameRules::BeginHaunting

local function HauntWorld(t)
	local world = {
		random = FakeActor.Random(t.random or { 0 }),
		players = t.players or {},
		areas = t.areas or {},
	}
	function world:RandomInt(lo, hi) return self.random:Int(lo, hi) end
	function world:RandomFloat(lo, hi) return self.random:Float(lo, hi) end
	function world:LivingPlayerOrigins() return self.players end
	function world:SpawnAreaCenters() return self.areas end
	return world
end

T.test("a haunting brings ghosts up to the count, away from players", function()
	local world = HauntWorld({
		players = { V(0, 0, 0) },
		areas = { V(100, 0, 0), V(1000, 0, 0) },
		random = { 0.5 },
	})
	local plan = Ghost.Haunt(world, {}, 4, 10, 20)
	T.eq(#plan.spawn, 4, "four")
	for _, ghost in ipairs(plan.spawn) do
		T.eq(ghost.pos, V(1000, 0, 0), "not within 240 of a player")
		T.near(ghost.lifetime, 15, EPSILON, "between the durations")
	end
end)

T.test("ghosts already haunting live on, with new lifetimes, and count", function()
	local world = HauntWorld({
		areas = { V(1000, 0, 0) },
		random = { 1 },
	})
	local plan = Ghost.Haunt(world, { "old" }, 4, 10, 20)
	T.eq(plan.extend[1].ghost, "old", "the old ghost")
	T.near(plan.extend[1].lifetime, 20, EPSILON, "a new lifetime")
	T.eq(#plan.spawn, 3, "three more")
	T.eq(#Ghost.Haunt(world, { 1, 2, 3, 4, 5 }, 4, 10, 20).spawn, 0, "enough already")
	T.eq(#Ghost.Haunt(HauntWorld({}), {}, 4, 10, 20).spawn, 0, "nowhere to haunt")
end)

T.test("haunting needs Halloween, and the boss's scenario or the holiday's allowHaunting", function()
	T.eq(Ghost.HauntingAllowed(false, true, true), false, "not Halloween")
	T.eq(Ghost.HauntingAllowed(true, true, false), true, "lakeside")
	T.eq(Ghost.HauntingAllowed(true, false, true), true, "allowHaunting")
	T.eq(Ghost.HauntingAllowed(true, false, false), false, "neither")
end)

T.finish()
