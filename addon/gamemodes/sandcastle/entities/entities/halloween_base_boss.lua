-- halloween_base_boss (CHalloweenBaseBoss): the base of the Halloween
-- bosses, a ws_combat_nextbot whose variant is a
-- foundation.npc.halloween_boss part. It implements the boss port
-- (foundation.npc.halloween_boss.METHODS) and passes the boss's convars in
-- its config. A subclass sets ENT.Variant. The npc feature adds the
-- particle files (features/npc/sh.lua) and precaches the variant's PARTICLES.
--
-- Configure{ team, owner } before Spawn (SpawnBossAtPos; the caller spawns
-- 10 above the spot: foundation.npc.halloween_boss.SpawnAt). A map's boss
-- takes its team from TeamNum/teamnum, else UNASSIGNED.
AddCSLuaFile()

ENT.Base = "ws_combat_nextbot"
ENT.Type = "nextbot"
ENT.Spawnable = false

if CLIENT then return end

-- GMod looks up Entity and NextBot methods before the entity's own table,
-- so no port method here shares an engine method's name.
local Base = baseclass.Get("ws_combat_nextbot")

-- TF2's convars for this boss (its variant's CONVARS), created by the first
-- binding, and their values now (the npc controller's BossConvars); and
-- whether sv_cheats is on as it spawns (m_wasSpawnedByCheats).
function ENT:Config()
	local configured = self.configured or {}
	return {
		team = configured.team,
		owner = configured.owner,
		convars = WS.Feature("npc"):BossConvars(WS.require(self.Variant).CONVARS),
		cheats = GetConVar("sv_cheats"):GetBool(),
	}
end

-- The model and owner come first: the variant's NewState reads both.
function ENT:Initialize()
	local variant = WS.require(self.Variant)
	self:SetModel(variant.MODEL)
	local owner = self:Config().owner
	if IsValid(owner) then self:SetOwner(owner) end
	Base.Initialize(self)
end

-- The actor port's owner is nil when there is none (GetOwner gives NULL).
function ENT:GetOwnerEntity()
	local owner = self:GetOwner()
	if IsValid(owner) then return owner end
	return nil
end

-------------------------------------------------------------------------------
-- The boss port (foundation.npc.halloween_boss.METHODS)

-- CHalloweenBaseBoss::Break: the model's gibs, broken client-side.
function ENT:Break()
	self:GibBreakClient(vector_origin)
end

-- A boss game event (foundation.npc.boss_events, defined by the npc
-- feature) to every client, whose npc view plays its cue.
function ENT:FireGameEvent(name, fields)
	WS.Events.Fire(name, fields)
end
