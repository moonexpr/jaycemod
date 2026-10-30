-- Part of the AI war controller (sv.lua): what each team knows of the enemy,
-- by room (wartactics.intel on wartactics.rooms, docs/special-missions-plan.md
-- §2.2). Every INTEL_INTERVAL each soldier's enemy in sight is a sighting
-- in that enemy's room: a floor turret a turret, a medic a medic (its role,
-- or a player medic's), anything else a soldier; our soldiers and players
-- dying are losses where they fell; an enemy killed is gone from what its
-- foes know. Nothing is known before the map's rooms are (Rooms).
local Controller = ...
local Intel = wartactics.intel
local AiWar = WS.require("features.aiwar.model")
local Teams = gameplay.teams

local INTEL_INTERVAL = 1
local KIND_OF_CLASS = {
	npc_turret_floor = Intel.TURRET,
}

-- The team's intel, made when first asked.
function Controller:Intel(team)
	self.intel = self.intel or {}
	if not self.intel[team] then self.intel[team] = Intel.New() end
	return self.intel[team]
end

-- The room id of a position, or nil (no rooms yet, or in none).
function Controller:RoomAt(pos)
	local rooms = self.rooms
	if not rooms then return nil end
	local area = navmesh.GetNearestNavArea(pos)
	local room = IsValid(area) and rooms.of[area:GetID()]
	return room and room.id or nil
end

function Controller:EnemyKind(enemy)
	local kind = KIND_OF_CLASS[enemy:GetClass()]
	if kind then return kind end
	local member = self.war and self.war:Member(enemy)
	if member and member.role == AiWar.MEDIC then return Intel.MEDIC end
	return Intel.SOLDIER
end

function Controller:SightThink(now)
	for ent, entry in pairs(self.soldiers) do
		local soldier = entry.soldier
		if IsValid(ent) and soldier:IsAlive() and soldier:HasEnemy() then
			local enemy = soldier:Enemy()
			local room = IsValid(enemy) and self:RoomAt(enemy:GetPos())
			if room then self:Intel(soldier.team):Sight(room, self:EnemyKind(enemy), enemy, now) end
		end
	end
end

local nextSight = 0

hook.Add("Think", "ws_aiwar_intel", function()
	local now = CurTime()
	if not Controller.war or now < nextSight then return end
	nextSight = now + INTEL_INTERVAL
	Controller:Rooms()
	Controller:SightThink(now)
end)

-- Someone fell: a loss where it fell for its team; gone from its enemy's
-- knowledge.
local function Fell(victim)
	if not (Controller.war and Controller.intel) then return end
	local team = WS.LastTeamNumber(victim)
	local room = Controller:RoomAt(victim:GetPos())
	if room and Controller.intel[team] then Controller.intel[team]:Loss(room, CurTime()) end
	local enemy = Teams.EnemyOf(team)
	if enemy and Controller.intel[enemy] then Controller.intel[enemy]:Gone(victim) end
end

hook.Add("OnNPCKilled", "ws_aiwar_intel", Fell)
hook.Add("PlayerDeath", "ws_aiwar_intel", Fell)
hook.Add("EntityRemoved", "ws_aiwar_intel", function(ent)
	if not Controller.intel then return end
	for _, intel in pairs(Controller.intel) do intel:Gone(ent) end
end)
