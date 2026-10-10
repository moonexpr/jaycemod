local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local FakeCombatant = dofile("tests/fake_combatant.lua")
local Combat = T.require("foundation.combat")
local Teams = T.require("foundation.teams")
local Actor = T.require("foundation.npc.actor")
local Combatant = T.require("foundation.npc.combatant")
local Players = T.require("foundation.players")

local V = Fake.Vector

local RADIUS = 146 -- a rocket's
local DAMAGE = 90

local function Explosion(overrides)
	local config = {
		origin = V(0, 0, 0),
		radius = RADIUS,
		damage = DAMAGE,
		attackerTeam = Teams.RED,
		attacker = "attacker",
		halfFalloff = false,
		forceFriendlyFire = false,
		crit = false,
	}
	for k, v in pairs(overrides or {}) do config[k] = v end
	return Combat.Explosion.New(config)
end

-- A BLU player in the open unless the case says otherwise.
local function Victim(overrides)
	local victim = {
		team = Teams.BLUE,
		isAttacker = false,
		distance = 0,
		visible = true,
	}
	for k, v in pairs(overrides or {}) do victim[k] = v end
	return victim
end

T.test("the crit multiplier is TF2's", function()
	T.defined(Combat.CRIT_MULTIPLIER, "TF_DAMAGE_CRIT_MULTIPLIER")
end)

-- CTFRadiusDamageInfo::CalculateFalloff and ApplyToEntity

T.test("full damage at the centre, damage times damage/radius at the edge", function()
	local e = Explosion()
	T.near(e:DamageTo(Victim({ distance = 0 })), DAMAGE, 1e-9, "centre")
	T.near(e:DamageTo(Victim({ distance = RADIUS })), DAMAGE * DAMAGE / RADIUS, 1e-9, "edge")
	T.near(e:DamageTo(Victim({ distance = RADIUS / 2 })), (DAMAGE + DAMAGE * DAMAGE / RADIUS) / 2, 1e-9, "halfway")
end)

T.test("half falloff halves the damage at the edge", function()
	local e = Explosion({ halfFalloff = true })
	T.near(e:DamageTo(Victim({ distance = 0 })), DAMAGE, 1e-9, "centre")
	T.near(e:DamageTo(Victim({ distance = RADIUS })), DAMAGE / 2, 1e-9, "edge")
	T.near(e:DamageTo(Victim({ distance = RADIUS / 2 })), DAMAGE * 0.75, 1e-9, "halfway")
end)

T.test("beyond the radius the damage stays at the edge's", function()
	local e = Explosion({ halfFalloff = true })
	T.near(e:DamageTo(Victim({ distance = 2 * RADIUS })), DAMAGE / 2, 1e-9, "clamped")
end)

T.test("a crit triples what the falloff leaves", function()
	local e = Explosion({
		halfFalloff = true,
		crit = true,
	})
	T.near(e:DamageTo(Victim({ distance = RADIUS })), DAMAGE / 2 * Combat.CRIT_MULTIPLIER, 1e-9, "crit edge")
end)

T.test("an explosion with no radius hurts nobody", function()
	T.eq(Explosion({ radius = 0 }):DamageTo(Victim()), nil, "no radius")
end)

-- Sides

T.test("an enemy is hurt, a teammate is not, and the attacker hurts itself", function()
	local e = Explosion()
	T.eq(e:DamageTo(Victim({ team = Teams.BLUE })), DAMAGE, "enemy")
	T.eq(e:DamageTo(Victim({ team = Teams.RED })), nil, "teammate")
	T.eq(e:DamageTo(Victim({
		team = Teams.RED,
		isAttacker = true,
	})), DAMAGE, "self")
	T.eq(e:DamageTo(Victim({ team = Teams.HALLOWEEN })), DAMAGE, "a skeleton")
end)

T.test("forced friendly fire hurts teammates too", function()
	local e = Explosion({ forceFriendlyFire = true })
	T.eq(e:DamageTo(Victim({ team = Teams.RED })), DAMAGE, "teammate")
end)

T.test("a Halloween explosion spares Halloween NPCs and hurts both teams", function()
	local e = Explosion({ attackerTeam = Teams.HALLOWEEN })
	T.eq(e:DamageTo(Victim({ team = Teams.HALLOWEEN })), nil, "skeleton")
	T.eq(e:DamageTo(Victim({ team = Teams.RED })), DAMAGE, "red")
	T.eq(e:DamageTo(Victim({ team = Teams.BLUE })), DAMAGE, "blue")
end)

T.test("an explosion with no team has no teammates", function()
	local e = Explosion({ attackerTeam = Teams.UNASSIGNED })
	T.eq(e:DamageTo(Victim({ team = Teams.UNASSIGNED })), DAMAGE, "a teamless prop")
end)

-- Line of sight: nothing passes through the world.

T.test("a victim the blast cannot see is not hurt, whatever its side", function()
	local e = Explosion({ forceFriendlyFire = true })
	T.eq(e:DamageTo(Victim({ visible = false })), nil, "enemy behind a wall")
	T.eq(e:DamageTo(Victim({
		team = Teams.RED,
		isAttacker = true,
		visible = false,
	})), nil, "self behind a wall")
end)

-- Distance: the nearer of the centre and the origin; a direct hit is 0.

T.test("the distance is to the nearer of the victim's centre and origin", function()
	local e = Explosion({ origin = V(0, 0, 100) })
	T.eq(e:DistanceTo(V(30, 40, 100), V(30, 40, 64)), 50, "centre nearer")
	T.eq(e:DistanceTo(V(0, 0, 36), V(0, 0, 90)), 10, "origin nearer")
	T.eq(e:DistanceTo(V(30, 40, 100), V(30, 40, 64), true), 0, "direct hit")
end)

T.test("a whole blast: a rocket among a crowd", function()
	local e = Explosion({ origin = V(0, 0, 0) })
	local crowd = {
		{
			name = "enemy at the blast",
			team = Teams.BLUE,
			center = V(0, 0, 36),
			origin = V(0, 0, 0),
			visible = true,
			expected = DAMAGE,
		},
		{
			name = "enemy hit directly",
			team = Teams.BLUE,
			center = V(100, 0, 36),
			origin = V(100, 0, 0),
			visible = true,
			direct = true,
			expected = DAMAGE,
		},
		{
			name = "enemy at the edge",
			team = Teams.BLUE,
			center = V(RADIUS, 0, 36),
			origin = V(RADIUS, 0, 0),
			visible = true,
			expected = DAMAGE * DAMAGE / RADIUS,
		},
		{
			name = "enemy behind a wall",
			team = Teams.BLUE,
			center = V(50, 0, 36),
			origin = V(50, 0, 0),
			visible = false,
		},
		{
			name = "teammate",
			team = Teams.RED,
			center = V(10, 0, 36),
			origin = V(10, 0, 0),
			visible = true,
		},
	}
	for _, v in ipairs(crowd) do
		local amount = e:DamageTo({
			team = v.team,
			isAttacker = false,
			distance = e:DistanceTo(v.center, v.origin, v.direct),
			visible = v.visible,
		})
		if v.expected then
			T.near(amount, v.expected, 1e-9, v.name)
		else
			T.eq(amount, nil, v.name)
		end
	end
end)

-- The combatant port contract

local ENTITIES = "addon/gamemodes/sandcastle/entities/entities/"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

T.test("the fake combatant implements every actor and combatant method", function()
	local me = FakeCombatant.Combatant({ world = FakeCombatant.World() })
	for _, name in ipairs(Actor.METHODS) do
		T.eq(type(me[name]), "function", "actor " .. name)
	end
	for _, name in ipairs(Combatant.METHODS) do
		T.eq(type(me[name]), "function", "combatant " .. name)
	end
end)

T.test("ws_combat_nextbot defines every combatant method", function()
	local text = ReadFile(ENTITIES .. "ws_combat_nextbot.lua")
	for _, name in ipairs(Combatant.METHODS) do
		T.eq(text:find("function ENT:" .. name .. "(", 1, true) ~= nil, true, "ws_combat_nextbot " .. name)
	end
end)

T.test("no combatant method shadows an actor or engine method", function()
	local taken = {}
	for _, name in ipairs(Actor.METHODS) do taken[name] = true end
	for name in pairs(Actor.ENGINE) do taken[name] = true end
	for _, name in ipairs(Combatant.METHODS) do
		T.eq(taken[name], nil, "combatant " .. name)
	end
end)

-- An entity file loads nothing at top level: every WS.require and
-- WS.Feature call is inside a function, so indented or on a one-line
-- function.
local function LoadsAtTopLevel(line)
	if line:match("^%s") or line:match("^function ") then return false end
	return line:find("WS.require", 1, true) ~= nil or line:find("WS.Feature", 1, true) ~= nil
end

T.test("a top-level load is caught", function()
	T.eq(LoadsAtTopLevel('local Combat = WS.Feature("combat")'), true, "top level")
	T.eq(LoadsAtTopLevel('\tself.combat = WS.Feature("combat")'), false, "in a function")
	T.eq(LoadsAtTopLevel('function ENT:Tag() return WS.Feature("tag") end'), false, "one-line function")
end)

T.test("the combat and holiday bindings load nothing at top level", function()
	for _, file in ipairs({ "ws_combat_nextbot.lua", "tf_logic_holiday.lua" }) do
		for line in ReadFile(ENTITIES .. file):gmatch("[^\n]+") do
			T.eq(LoadsAtTopLevel(line), false, file .. ": " .. line)
		end
	end
end)

-- The fake combatant: a world of players and NPCs the models can ask about.

T.test("the fake collects living players by team, RED and BLU by default", function()
	local world = FakeCombatant.World()
	local red = world:AddPlayer({ team = Teams.RED })
	local blue = world:AddPlayer({ team = Teams.BLUE })
	world:AddPlayer({
		team = Teams.BLUE,
		alive = false,
	})
	world:AddPlayer({ team = Teams.SPECTATOR })
	local me = FakeCombatant.Combatant({
		world = world,
		team = Teams.HALLOWEEN,
	})
	T.eq(me:GetTeamNumber(), Teams.HALLOWEEN, "my team")
	T.eq(me:TeamOf(red), Teams.RED, "their team")
	local blues = me:CollectPlayers(Teams.BLUE)
	T.eq(#blues, 1, "one living blue")
	T.eq(blues[1], blue, "the living one")
	T.eq(#me:CollectPlayers(nil), 2, "red and blue")
end)

T.test("the fake reports conditions, invulnerability and effects", function()
	local world = FakeCombatant.World()
	local ubered = world:AddPlayer({
		team = Teams.RED,
		conds = { Players.COND.INVULNERABLE },
	})
	local me = FakeCombatant.Combatant({ world = world })
	T.eq(me:InCond(ubered, Players.COND.INVULNERABLE), true, "in cond")
	T.eq(me:IsInvulnerable(ubered), true, "invulnerable")
	me:AddCond(ubered, Players.COND.URINE, 10)
	T.eq(me:InCond(ubered, Players.COND.URINE), true, "cond added")
	me:StunPlayer(ubered, 2, 0, Players.STUN.LOSER_STATE)
	T.eq(#me:Called("StunPlayer"), 1, "stun recorded")
	me:Explode({ damage = 10 })
	T.eq(me:Called("Explode")[1][1].damage, 10, "explosion recorded")
end)

T.finish()
