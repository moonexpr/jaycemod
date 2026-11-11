-- npc_ctfbot: MvM's bomb carrier, on the engine's own statechart (native/nextsoldier):
-- nextsoldier.behavior.ctfbot's actions under its native monitors. Spawned, it is
-- given the map's item_teamflag and runs it to the func_capturezone, with no round or
-- wave around it. What it does is theirs.
AddCSLuaFile ()

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

WS.WarSoldier (ENT)

if CLIENT then return end

local CTFBot = nextsoldier.behavior.ctfbot

local SoldierInitialize = ENT.CustomInitialize

function ENT:CustomInitialize ()
	SoldierInitialize (self)
	self.NSRun = true
	self.ctfbotSpawnedAt = CurTime ()
	WS.SetTeamMember (self, WS.TEAM_BLUE)
	-- with no war to do it (its SetForcefieldsPassable): TF2's forcefields stop only
	-- players, but a NextBot's movement takes one for a wall, and the nav mesh, until
	-- it next looks, the areas under it for blocked
	for _, forcefield in ipairs (ents.FindByClass ("func_respawnroomvisualizer")) do forcefield:SetNotSolid (true) end
end

local compiled

function ENT:NSInitialAction ()
	compiled = compiled or CTFBot.Compile (wartactics.scenarios)
	return CTFBot.InitialAction (nextsoldier.engine, compiled)
end

WS.require ("features.flag.soldier").Apply (ENT)

function ENT:FlagCarrier () return self end
function ENT:SecondsAlive () return CurTime () - self.ctfbotSpawnedAt end
function ENT:Now () return CurTime () end
function ENT:RoundMode () return WS.Feature ("rounds"):Mode ().NAME end
