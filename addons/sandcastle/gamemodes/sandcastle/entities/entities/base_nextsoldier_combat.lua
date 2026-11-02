-- base_nextsoldier_combat: a base_nextsoldier_npc that also implements the
-- combatant port (games.npc.combatant) through
-- the combat, holiday and npc controllers and the gamemode's player
-- conditions. A subclass sets ENT.Variant as for base_nextsoldier_npc.
--
-- Its team is config.team when its config has one, else its TeamNum
-- keyvalue, else UNASSIGNED.
AddCSLuaFile()

ENT.Base = "base_nextsoldier_npc"
ENT.Type = "nextbot"
ENT.Spawnable = false

if CLIENT then return end

-- GMod looks up Entity and NextBot methods before the entity's own table,
-- so no port method here may share an engine method's name (games_gameplay_combat_test
-- checks the port's names against foundation.npc.actor.ENGINE).
local Base = baseclass.Get("base_nextsoldier_npc")

-- TeamNum is read as TF2 reads it (atoi): a non-number is 0, UNASSIGNED.
function ENT:KeyValue(key, value)
	if string.lower(key) == "teamnum" then self.teamKeyValue = tonumber(value) or WS.TEAM_UNASSIGNED end
	Base.KeyValue(self, key, value)
end

-- The team is set before the model binds, since its NewState may ask.
function ENT:Initialize()
	local config = self:Config()
	self.team = (config and config.team) or self.teamKeyValue or WS.TEAM_UNASSIGNED
	self.combat = WS.Feature("combat")
	self.holiday = WS.Feature("holiday")
	self.targeting = npc.targeting
	Base.Initialize(self)
end

-------------------------------------------------------------------------------
-- The combatant port (foundation.npc.combatant.METHODS)

-- sides
function ENT:GetTeamNumber() return self.team end
function ENT:Team() return self.team end
function ENT:TeamOf(t) return self.combat:TeamOf(t) end

function ENT:CollectPlayers(team)
	local found = {}
	for _, ply in ipairs(player.GetAll()) do
		local playerTeam = ply:Team()
		local wanted
		if team == nil then
			wanted = playerTeam == WS.TEAM_RED or playerTeam == WS.TEAM_BLUE
		else
			wanted = playerTeam == team
		end
		if wanted and ply:Alive() then found[#found + 1] = ply end
	end
	return found
end

function ENT:CollectNPCs(kind) return self.npcs:All(kind) end
function ENT:CollectMembers(team) return WS.TeamMembers(team) end

-- conditions: only players have them.
function ENT:InCond(t, cond)
	if not t:IsPlayer() then return false end
	return WS.InCondition(t, cond)
end

function ENT:IsInvulnerable(t)
	return self.targeting.IsInvulnerable(function(cond) return self:InCond(t, cond) end)
end

function ENT:InRespawnRoom(t) return self.combat:InRespawnRoom(t) end

function ENT:StunPlayer(t, duration, reduction, flags)
	if t:IsPlayer() then WS.StunPlayer(t, duration, reduction, flags) end
end

function ENT:AddCond(t, cond, duration)
	if t:IsPlayer() then WS.AddCondition(t, cond, duration) end
end

-- the game
-- CTeamplayRoundBasedRules::RoundHasBeenWon
function ENT:RoundHasBeenWon() return WS.State() == WS.STATE.TEAM_WIN end
function ENT:DropSpellPickup(v, tier) self.holiday:DropSpellPickup(v, tier) end
function ENT:Explode(config) self.combat:Explode(config) end
function ENT:HolidayActive(h) return self.holiday:HolidayActive(h) end
function ENT:Tag() return WS.Feature("tag") end
function ENT:SetBossHealth(fraction) self.npcs:SetBossHealth(fraction) end

function ENT:SpawnPoints(name)
	local points = {}
	for _, ent in ipairs(ents.FindByName(name)) do points[#points + 1] = ent:GetPos() end
	return points
end
