-- npc_ctfbot: MvM's bomb carrier, on the engine's own statechart (native/nextsoldier):
-- nextsoldier.behavior.ctfbot's actions under its native TacticalMonitor. Spawned, it
-- is given the map's item_teamflag and runs it to the func_capturezone, with no round
-- or wave around it. What it does is theirs; this is what they ask of the flag feature.
AddCSLuaFile()

ENT.Base = "base_nextsoldier"
ENT.Type = "nextbot"
ENT.PrintName = "CTFBot"
ENT.Category = "Sandcastle"
ENT.Spawnable = false
ENT.Model = "models/player/combine_soldier.mdl"
ENT.Weapons = {}
ENT.Factions = {}
ENT.DefaultRelationship = D_NU
ENT.RagdollOnDeath = false

WS.WarSoldier(ENT)

if CLIENT then return end

local CTFBot = nextsoldier.behavior.ctfbot
local FlagModel = WS.require("features.flag.model")

local SoldierInitialize = ENT.CustomInitialize

function ENT:CustomInitialize()
	SoldierInitialize(self)
	self.NSRun = true
	self.ctfbotSpawnedAt = CurTime()
	WS.SetTeamMember(self, WS.TEAM_BLUE)
end

function ENT:NSInitialAction() return CTFBot.InitialAction(nextsoldier.engine) end

-- Its team's flag (MvM's bomb is the invaders' own): the entity and its model.
local function Bomb(self)
	local team = WS.TeamNumber(self)
	for _, ent in ipairs(ents.FindByClass("item_teamflag")) do
		local model = ent.flag:FlagAt(ent)
		if model:Enabled() and model:Team() == team then return ent, model end
	end
	return nil
end

function ENT:HasTheFlag()
	local _, model = Bomb(self)
	return model ~= nil and model:Carrier() == self
end

function ENT:IsFlagHome()
	local _, model = Bomb(self)
	return model ~= nil and model:State() == FlagModel.HOME
end

function ENT:SecondsAlive() return CurTime() - self.ctfbotSpawnedAt end

function ENT:PickUpFlag()
	local ent = Bomb(self)
	return ent ~= nil and ent.flag:Give(ent, self)
end

function ENT:LooseFlag()
	local ent, model = Bomb(self)
	if model and model:State() == FlagModel.DROPPED then return ent:GetPos() end
	return nil
end

function ENT:FlagCaptureZone()
	local team = WS.TeamNumber(self)
	for _, zone in ipairs(ents.FindByClass("func_capturezone")) do
		if zone.flag:ZoneTeam(zone) == team then return zone:LocalToWorld(zone:OBBCenter()) end
	end
	return nil
end

function ENT:Now() return CurTime() end
