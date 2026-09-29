-- An in-memory foundation.npc.combatant for model tests: a fake actor
-- (tests/fake_actor.lua) that also takes sides, in a World of players and
-- NPCs. It implements every name in foundation.npc.actor.METHODS and
-- foundation.npc.combatant.METHODS (combat_test checks that), and logs every
-- effect in the actor's call log (me:Called(name)).
--
--   local world = FakeCombatant.World()
--   local red = world:AddPlayer({ team = Teams.RED, origin = V(100, 0, 0) })
--   local me = FakeCombatant.Combatant({ world = world, team = Teams.HALLOWEEN })
local Fake = dofile("tests/fake_actor.lua")
local H = dofile("tests/harness.lua")
local Teams = H.require("foundation.teams")
local Targeting = H.require("foundation.npc.targeting")

local FakeCombatant = {}

for k, v in pairs(Fake) do FakeCombatant[k] = v end

local function Set(list)
	local set = {}
	for _, v in ipairs(list or {}) do set[v] = true end
	return set
end

-- Tag: the tag controller's Get and Set, remembering who is IT.
local Tag = {}
Tag.__index = Tag

function Tag:Get() return self.it end
function Tag:Set(ply) self.it = ply end

-- World: what every combatant in a test sees.
local World = {}
World.__index = World

function FakeCombatant.World()
	return setmetatable({
		players = {},
		npcs = {},
		members = {},
		roundWon = false,
		holidays = {},
		spawnPoints = {},
		tag = setmetatable({}, Tag),
	}, World)
end

-- A player: a fake target with a team, conditions (a list of COND values)
-- and whether it stands in a respawn room.
function World:AddPlayer(t)
	local ply = Fake.Target(t)
	ply.team = t.team or Teams.UNASSIGNED
	ply.conds = Set(t.conds)
	ply.inRespawnRoom = t.inRespawnRoom == true
	self.players[#self.players + 1] = ply
	return ply
end

-- A team member that is not a player (an AI war soldier): a fake target
-- with a team.
function World:AddMember(t)
	local member = Fake.Target(t)
	member.team = t.team or Teams.UNASSIGNED
	member.conds = {}
	self.members[#self.members + 1] = member
	return member
end

-- An NPC of a registry kind: a fake combatant, or a fake target with a team.
function World:AddNPC(kind, npc)
	npc.conds = npc.conds or {}
	self.npcs[kind] = self.npcs[kind] or {}
	table.insert(self.npcs[kind], npc)
	return npc
end

function World:SetHoliday(h, on) self.holidays[h] = on end
function World:SetRoundWon(won) self.roundWon = won end
function World:SetSpawnPoints(name, points) self.spawnPoints[name] = points end

-- The combatant: a fake actor with a world and a team.
local ActorClass = getmetatable(Fake.Actor())
local Combatant = setmetatable({}, { __index = ActorClass })
Combatant.__index = Combatant

-- t: fake_actor's fields, plus world and team (default UNASSIGNED).
function FakeCombatant.Combatant(t)
	local me = Fake.Actor(t)
	me.world = t.world
	me.team = t.team or Teams.UNASSIGNED
	me.conds = {}
	me.inRespawnRoom = false
	return setmetatable(me, Combatant)
end

-- sides
function Combatant:GetTeamNumber() return self.team end
function Combatant:TeamOf(t) return t.team or Teams.UNASSIGNED end

function Combatant:CollectPlayers(team)
	local found = {}
	for _, ply in ipairs(self.world.players) do
		local wanted = team == nil and (ply.team == Teams.RED or ply.team == Teams.BLUE) or ply.team == team
		if wanted and ply.alive then found[#found + 1] = ply end
	end
	return found
end

function Combatant:CollectMembers(team)
	local found = {}
	for _, member in ipairs(self.world.members) do
		if member.team == team and member.alive ~= false then found[#found + 1] = member end
	end
	return found
end

function Combatant:CollectNPCs(kind)
	local found = {}
	for i, npc in ipairs(self.world.npcs[kind] or {}) do found[i] = npc end
	return found
end

-- conditions
function Combatant:InCond(t, cond) return t.conds[cond] == true end

function Combatant:IsInvulnerable(t)
	return Targeting.IsInvulnerable(function(cond) return self:InCond(t, cond) end)
end

function Combatant:InRespawnRoom(t) return t.inRespawnRoom end

function Combatant:StunPlayer(t, duration, reduction, flags)
	self:Record("StunPlayer", t, duration, reduction, flags)
end

function Combatant:AddCond(t, cond, duration)
	t.conds[cond] = true
	self:Record("AddCond", t, cond, duration)
end

-- the game
function Combatant:RoundHasBeenWon() return self.world.roundWon end
function Combatant:DropSpellPickup(v, tier) self:Record("DropSpellPickup", v, tier) end
function Combatant:Explode(config) self:Record("Explode", config) end
function Combatant:HolidayActive(h) return self.world.holidays[h] == true end
function Combatant:Tag() return self.world.tag end
function Combatant:SetBossHealth(fraction) self:Record("SetBossHealth", fraction) end
function Combatant:SpawnPoints(name) return self.world.spawnPoints[name] or {} end

return FakeCombatant
