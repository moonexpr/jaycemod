local T = dofile("tests/harness.lua")
local FakeCombatant = dofile("tests/fake_combatant.lua")
local NpcSystem = T.require("foundation.npc")
local HalloweenBoss = T.require("foundation.npc.halloween_boss")
local Teams = T.require("foundation.teams")

local V = FakeCombatant.Vector
local MAX_HEALTH = 1000
local BOSS_LEVEL = 3

T.test("the boss types and constants keep TF2's values", function()
	T.eq(HalloweenBoss.BOSS_INVALID, 0, "invalid")
	T.eq(HalloweenBoss.BOSS_HHH, 1, "HHH")
	T.eq(HalloweenBoss.BOSS_MONOCULUS, 2, "MONOCULUS")
	T.eq(HalloweenBoss.BOSS_MERASMUS, 3, "Merasmus")
	T.eq(HalloweenBoss.DPS_WINDOW, 5, "DPS window")
	T.eq(HalloweenBoss.KIND, "boss", "registry kind")
end)

T.test("a boss is a spell unless it is on the Halloween team", function()
	T.eq(HalloweenBoss.IsSpell(Teams.HALLOWEEN), false, "Halloween")
	T.eq(HalloweenBoss.IsSpell(Teams.RED), true, "RED")
	T.eq(HalloweenBoss.IsSpell(Teams.BLUE), true, "BLU")
	T.eq(HalloweenBoss.IsSpell(Teams.UNASSIGNED), true, "unassigned")
end)

-- CHalloweenBaseBoss::SpawnBossAtPos
T.test("SpawnAt names the boss's class, its config and a spot 10 above", function()
	local class, config, pos = HalloweenBoss.SpawnAt(HalloweenBoss.BOSS_MONOCULUS, V(1, 2, 3), Teams.RED, "owner", V)
	T.eq(class, "eyeball_boss", "class")
	T.eq(config.team, Teams.RED, "team")
	T.eq(config.owner, "owner", "owner")
	T.eq(pos, V(1, 2, 3 + HalloweenBoss.SPAWN_HEIGHT), "10 above")
	T.eq(HalloweenBoss.SPAWN_HEIGHT, 10, "the spawn height")
	T.eq((HalloweenBoss.SpawnAt(HalloweenBoss.BOSS_HHH, V(0, 0, 0), Teams.HALLOWEEN, nil, V)), "headless_hatman", "HHH")
end)

-- A boss variant whose hooks log when the template calls them.
local function TestBoss(log)
	local boss = {
		BOSS_TYPE = HalloweenBoss.BOSS_HHH,
		HOVER = { hoverHeight = 1 },
	}
	local Emerge = NpcSystem.Action:Extend("Emerge")
	function Emerge:OnStart(me) log[#log + 1] = "Emerge.OnStart" return self:Continue() end
	function Emerge:Update(me) log[#log + 1] = "Emerge.Update" return self:Continue() end
	function Emerge:OnEnd(me) log[#log + 1] = "Emerge.OnEnd" end
	local Dying = NpcSystem.Action:Extend("Dying")
	function Dying:OnStart(me) log[#log + 1] = "Dying.OnStart" return self:Continue() end

	function boss.Level(me)
		log[#log + 1] = "Level"
		return BOSS_LEVEL
	end
	function boss.Health(players, level, convars)
		log[#log + 1] = "Health"
		boss.healthArgs = {
			players = players,
			level = level,
			convars = convars,
		}
		return MAX_HEALTH
	end
	function boss.Setup(state, config, me) log[#log + 1] = "Setup" end
	function boss.ModifyDamage(state, damageEvent, me)
		log[#log + 1] = "ModifyDamage"
		return damageEvent.amount * (damageEvent.scale or 1)
	end
	function boss.EmergeAction(state)
		log[#log + 1] = "EmergeAction"
		return Emerge:New()
	end
	function boss.DyingAction(state)
		log[#log + 1] = "DyingAction"
		return Dying:New()
	end
	function boss.OnInjured(state, damageEvent, me) log[#log + 1] = "OnInjured" end
	function boss.OnUpdate(state, me) log[#log + 1] = "OnUpdate" end
	return HalloweenBoss.Variant(boss)
end

local function Scene(t)
	local world = FakeCombatant.World()
	local red = world:AddPlayer({
		team = Teams.RED,
		origin = V(500, 0, 0),
	})
	local blue = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(-500, 0, 0),
	})
	world:AddPlayer({
		team = Teams.BLUE,
		alive = false,
	})
	local me = FakeCombatant.Combatant({
		world = world,
		team = t.team or Teams.HALLOWEEN,
	})
	local log = {}
	local boss = TestBoss(log)
	local npc = NpcSystem.Npc.New(boss, { convars = { tf_test = 1 } }, me)
	return {
		world = world,
		me = me,
		red = red,
		blue = blue,
		log = log,
		boss = boss,
		npc = npc,
	}
end

local function Damage(attacker, amount, extra)
	local event = {
		attacker = attacker,
		amount = amount,
		dmgType = 0,
		crit = false,
	}
	for k, v in pairs(extra or {}) do event[k] = v end
	return event
end

local function Joined(log) return table.concat(log, ",") end

T.test("a boss is an NPC variant of kind boss, with the template's hooks", function()
	local s = Scene({})
	T.eq(s.boss.KIND, "boss", "kind")
	T.eq(type(s.boss.NewState), "function", "NewState")
	T.eq(type(s.boss.InitialAction), "function", "InitialAction")
	T.eq(type(s.boss.FilterDamage), "function", "FilterDamage")
	T.eq(s.boss.HOVER.hoverHeight, 1, "the variant's own fields stay")
end)

-- CHeadlessHatman::Spawn and CEyeballBoss::Spawn
T.test("at spawn the boss takes its level, then Health for the living RED and BLU players", function()
	local s = Scene({})
	T.eq(Joined(s.log), "Level,Health,Setup", "spawn order")
	T.eq(s.boss.healthArgs.players, 2, "living RED and BLU players")
	T.eq(s.boss.healthArgs.level, BOSS_LEVEL, "level")
	T.eq(s.boss.healthArgs.convars.tf_test, 1, "the binding's convars")
	T.eq(s.me:GetMaxHealth(), MAX_HEALTH, "max health")
	T.eq(s.me:GetHealth(), MAX_HEALTH, "health")
	local state = s.npc:State()
	T.eq(state.level, BOSS_LEVEL, "level kept")
	T.eq(state.spell, false, "not a spell")
	T.eq(state.team, Teams.HALLOWEEN, "team")
end)

T.test("a boss on RED is a spell", function()
	local s = Scene({ team = Teams.RED })
	T.eq(s.npc:State().spell, true, "spell")
end)

-- CHalloweenBaseBoss::OnTakeDamage_Alive
T.test("damage from my own team and after the round is won is refused before ModifyDamage", function()
	local s = Scene({ team = Teams.RED })
	local mate = s.world:AddPlayer({ team = Teams.RED })
	for i = #s.log, 1, -1 do s.log[i] = nil end
	T.eq(s.npc:FilterDamage(Damage(mate, 10)), false, "teammate")
	T.eq(s.npc:FilterDamage(Damage(s.blue, 10)), true, "enemy")
	s.world:SetRoundWon(true)
	T.eq(s.npc:FilterDamage(Damage(s.blue, 10)), false, "round won")
	T.eq(Joined(s.log), "ModifyDamage", "ModifyDamage only for the damage taken")
end)

T.test("a hit ModifyDamage takes to nothing is refused", function()
	local s = Scene({})
	T.eq(s.npc:FilterDamage(Damage(s.red, 10, { scale = 0 })), false, "zeroed")
	T.eq(#s.npc:State().attackers, 0, "not remembered")
end)

-- RememberAttacker
T.test("players who hurt the boss are remembered once each, with their latest time", function()
	local s = Scene({})
	local skeleton = s.world:AddNPC("zombie", FakeCombatant.Target({ team = Teams.RED }))
	s.npc:FilterDamage(Damage(s.red, 10))
	s.me.clock:Advance(1)
	s.npc:FilterDamage(Damage(s.blue, 10))
	s.me.clock:Advance(1)
	s.npc:FilterDamage(Damage(s.red, 10))
	s.npc:FilterDamage(Damage(s.world, 10))
	local attackers = s.npc:State().attackers
	T.eq(#attackers, 2, "red and blue")
	T.eq(attackers[1].attacker, s.red, "red first")
	T.eq(attackers[1].at, s.me:Now(), "red's latest hit")
	T.eq(attackers[2].attacker, s.blue, "blue")
	T.eq(s.npc:FilterDamage(Damage(skeleton, 10)), true, "an NPC's damage is taken")
	T.eq(#s.npc:State().attackers, 2, "but an NPC is not a player")
end)

-- UpdateDamagePerSecond: the damage of the last 5 s, per second.
T.test("the DPS counts the damage of the last 5 seconds and keeps its maximum", function()
	local s = Scene({})
	local state = s.npc:State()
	s.npc:Update(0.1) -- the first tick only starts the actions
	s.npc:FilterDamage(Damage(s.red, 500))
	s.npc:Update(0.1)
	T.near(state.dps, 100, 1e-9, "500 over the window")
	s.me.clock:Advance(2)
	s.npc:FilterDamage(Damage(s.red, 1000))
	s.npc:Update(0.1)
	T.near(state.dps, 300, 1e-9, "both hits")
	s.me.clock:Advance(3)
	s.npc:Update(0.1)
	T.near(state.dps, 300, 1e-9, "the first hit is exactly 5 s old")
	s.me.clock:Advance(0.5)
	s.npc:Update(0.1)
	T.near(state.dps, 200, 1e-9, "the first hit has aged out")
	s.me.clock:Advance(5)
	s.npc:Update(0.1)
	T.near(state.dps, 0, 1e-9, "all aged out")
	T.near(state.maxDps, 300, 1e-9, "the maximum stays")
end)

-- The template method: emerge first, the variant's hooks each tick and on
-- injury, and the dying action on death.
T.test("the template calls the variant's hooks in order, and dies into DyingAction", function()
	local s = Scene({})
	s.npc:Update(0.1)
	T.eq(Joined(s.log), "Level,Health,Setup,EmergeAction,Emerge.OnStart", "the first tick starts the actions")
	s.npc:Update(0.1)
	T.eq(Joined(s.log), "Level,Health,Setup,EmergeAction,Emerge.OnStart,Emerge.Update,OnUpdate", "the second runs them")
	T.eq(s.npc:Describe(), "BossBehavior/Emerge", "emerging")
	for i = #s.log, 1, -1 do s.log[i] = nil end
	s.npc:Event("OnInjured", Damage(s.red, 10))
	T.eq(Joined(s.log), "OnInjured", "injury")
	for i = #s.log, 1, -1 do s.log[i] = nil end
	s.me.alive = false
	s.npc:Event("OnKilled", Damage(s.red, 10))
	s.npc:Update(0.1)
	T.eq(Joined(s.log), "DyingAction,Emerge.OnEnd,Dying.OnStart", "death")
	T.eq(s.npc:Describe(), "Dying", "dying replaces the behavior")
end)

-- The bindings (read as text): each defines its port's methods as
-- function ENT:<Name>(, and loads nothing at file top level.
local ENTITIES = "addon/gamemodes/sandcastle/entities/entities/"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

local function Defines(file, name)
	return ReadFile(ENTITIES .. file):find("function ENT:" .. name .. "(", 1, true) ~= nil
end

-- An entity file loads nothing at top level: every WETSAND.require and
-- WETSAND.Feature call is inside a function.
local function LoadsAtTopLevel(line)
	if line:match("^%s") or line:match("^function ") then return false end
	return line:find("WETSAND.require", 1, true) ~= nil or line:find("WETSAND.Feature", 1, true) ~= nil
end

T.test("halloween_base_boss defines the boss port, and no boss method shadows another port's", function()
	local Actor = T.require("foundation.npc.actor")
	local Combatant = T.require("foundation.npc.combatant")
	local taken = {}
	for _, name in ipairs(Actor.METHODS) do taken[name] = true end
	for name in pairs(Actor.ENGINE) do taken[name] = true end
	for _, name in ipairs(Combatant.METHODS) do taken[name] = true end
	for _, name in ipairs(HalloweenBoss.METHODS) do
		T.eq(Defines("halloween_base_boss.lua", name), true, "halloween_base_boss " .. name)
		T.eq(taken[name], nil, "boss " .. name)
	end
end)

T.test("the boss bindings load nothing at top level", function()
	local files = {
		"halloween_base_boss.lua",
		"headless_hatman.lua",
		"eyeball_boss.lua",
		"teleport_vortex.lua",
		"tf_projectile_rocket.lua",
	}
	for _, file in ipairs(files) do
		for line in ReadFile(ENTITIES .. file):gmatch("[^\n]+") do
			T.eq(LoadsAtTopLevel(line), false, file .. ": " .. line)
		end
	end
end)

T.finish()
