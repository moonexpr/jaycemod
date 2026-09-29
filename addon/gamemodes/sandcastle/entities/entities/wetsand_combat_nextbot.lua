-- wetsand_combat_nextbot: an NPC that takes sides. It is a wetsand_nextbot
-- that also implements the combatant port (foundation.npc.combatant) through
-- the combat, holiday and npc controllers and the gamemode's player
-- conditions. A subclass sets ENT.Variant as for wetsand_nextbot.
--
-- Its team is config.team when its config has one, else its TeamNum
-- keyvalue, else UNASSIGNED.
AddCSLuaFile()

ENT.Base = "wetsand_nextbot"
ENT.Type = "nextbot"
ENT.Spawnable = false

if CLIENT then return end

-- GMod looks up Entity and NextBot methods before the entity's own table,
-- so no port method here may share an engine method's name (combat_test
-- checks the port's names against foundation.npc.actor.ENGINE).
local Base = baseclass.Get("wetsand_nextbot")

-- TeamNum is read as TF2 reads it (atoi): a non-number is 0, UNASSIGNED.
function ENT:KeyValue(key, value)
	if string.lower(key) == "teamnum" then self.teamKeyValue = tonumber(value) or WETSAND.TEAM_UNASSIGNED end
	Base.KeyValue(self, key, value)
end

-- The team is set before the model binds, since its NewState may ask.
function ENT:Initialize()
	local config = self:Config()
	self.team = (config and config.team) or self.teamKeyValue or WETSAND.TEAM_UNASSIGNED
	self.combat = WETSAND.Feature("combat")
	self.holiday = WETSAND.Feature("holiday")
	self.targeting = WETSAND.require("foundation.npc.targeting")
	Base.Initialize(self)
end

-------------------------------------------------------------------------------
-- The combatant port (foundation.npc.combatant.METHODS)

-- sides
function ENT:GetTeamNumber() return self.team end
function ENT:TeamOf(t) return self.combat:TeamOf(t) end

function ENT:CollectPlayers(team)
	local found = {}
	for _, ply in ipairs(player.GetAll()) do
		local playerTeam = ply:Team()
		local wanted
		if team == nil then
			wanted = playerTeam == WETSAND.TEAM_RED or playerTeam == WETSAND.TEAM_BLUE
		else
			wanted = playerTeam == team
		end
		if wanted and ply:Alive() then found[#found + 1] = ply end
	end
	return found
end

function ENT:CollectNPCs(kind) return self.npcs:All(kind) end
function ENT:CollectMembers(team) return WETSAND.TeamMembers(team) end

-- conditions: only players have them.
function ENT:InCond(t, cond)
	if not t:IsPlayer() then return false end
	return WETSAND.InCondition(t, cond)
end

function ENT:IsInvulnerable(t)
	return self.targeting.IsInvulnerable(function(cond) return self:InCond(t, cond) end)
end

function ENT:InRespawnRoom(t) return self.combat:InRespawnRoom(t) end

function ENT:StunPlayer(t, duration, reduction, flags)
	if t:IsPlayer() then WETSAND.StunPlayer(t, duration, reduction, flags) end
end

function ENT:AddCond(t, cond, duration)
	if t:IsPlayer() then WETSAND.AddCondition(t, cond, duration) end
end

-- the game
-- CTeamplayRoundBasedRules::RoundHasBeenWon
function ENT:RoundHasBeenWon() return WETSAND.State() == WETSAND.STATE.TEAM_WIN end
function ENT:DropSpellPickup(v, tier) self.holiday:DropSpellPickup(v, tier) end
function ENT:Explode(config) self.combat:Explode(config) end
function ENT:HolidayActive(h) return self.holiday:HolidayActive(h) end
function ENT:Tag() return WETSAND.Feature("tag") end
function ENT:SetBossHealth(fraction) self.npcs:SetBossHealth(fraction) end

function ENT:SpawnPoints(name)
	local points = {}
	for _, ent in ipairs(ents.FindByName(name)) do points[#points + 1] = ent:GetPos() end
	return points
end
