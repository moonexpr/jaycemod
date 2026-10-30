-- npc_civilian: a civilian, the body a hostage_entity spawns as its hostage
-- (cs_logic_hostage's bodyclass, by default), on NextSoldier's base
-- (base_nextsoldier) with the war soldier's movement (WS.WarSoldier: its
-- climbs, vaults, hops), as npc_pathfollower is. The hostage controller
-- (features/hostage) says whom it follows (SetLeader), arms it (Arm), sends
-- it for a pistol (Rush) and takes it out of the round (Rescued); its one
-- behaviour, in place of the base's intention, walks to that soldier and
-- stands otherwise. Whether it lives and whether it stands in a rescue zone
-- are its hostage_entity's to observe, not its own to tell. Unarmed
-- it fights nothing, is no one's target and cannot be hurt: RED keeps it, BLU
-- frees it, and the rescue is decided by the rules, not by a corpse. The one
-- the round arms (features.hostage.pistol) is BLU's side but keeps its gun
-- hidden while held, among its guards: freed and following a rescuer, it
-- shoots at RED in sight without leaving its way for it, and once it has
-- fired it is seen for what it is, a target that can be shot and killed.
-- One told to rush for a pistol lying runs to it before anything else.
AddCSLuaFile()

ENT.Base = "base_nextsoldier"
ENT.Type = "nextbot"
ENT.PrintName = "Civilian"
ENT.Spawnable = false
ENT.Weapons = {}
ENT.Factions = {}
ENT.DefaultRelationship = D_NU
ENT.RagdollOnDeath = false
ENT.WalkSpeed = 120
ENT.RunSpeed = 190

WS.WarSoldier(ENT)

if CLIENT then return end

-- The hostage stops this far from its rescuer.
local FOLLOW_GAP = 90
-- Armed, it looks about every LOOK_INTERVAL and fires at RED within
-- DEFEND_RANGE (a pistol's reach: features.aiwar.arms').
local LOOK_INTERVAL = 0.3
local DEFEND_RANGE = 750
local ARMED_HEALTH = 100
-- Glass (a func_breakable_surf window) within GLASS_REACH ahead of it as it
-- walks it breaks, as a player would: its route may go through a window the
-- soldiers shot out, or one still whole.
local GLASS_REACH = 32
local GLASS_DAMAGE = 100
local Factions = WS.require("ws.factions")
local Weapons = nextsoldier.weapons

local SoldierInitialize = ENT.CustomInitialize
function ENT:CustomInitialize()
	SoldierInitialize(self)
	self:SetModel(WS.require("features.hostage.models").Pick(self:EntIndex()))
	self:SetNoTarget(true)
	-- players walk through it (ws_nextbot's PLAYERS_PASS_THROUGH group): a
	-- rescuer turning back for it in a narrow hall is not walled in by it
	self:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
	self.NSRun = true
end

-- No hurt reaches it until it has fired (Revealed).
function ENT:OnInjured(dmg)
	if not self.revealed then
		dmg:SetDamage(0)
		return
	end
	self.BaseClass.OnInjured(self, dmg)
end

-- Armed with class's gun, its magazine stats (nextsoldier.weapons'): BLU's
-- side, hostile to RED, its gun hidden until it fires.
function ENT:Arm(class, stats)
	local weapon = self:GiveWeapon(class)
	self.nsMagazines[weapon] = Weapons.Magazine(stats)
	self:SelectWeapon(weapon)
	self.armed, self.rushTo = true, nil
	self:SetHealth(ARMED_HEALTH)
	self:SetMaxHealth(ARMED_HEALTH)
	self:JoinFaction(Factions.Of(WS.TEAM_BLUE))
	self:SetFactionRelationship(Factions.Of(WS.TEAM_RED), D_HT, 1)
end

-- Whether it has fired, and so is a target and can be hurt.
function ENT:Revealed() return self.revealed == true end

-- Where to rush (a pistol lying), or nil.
function ENT:Rush(pos)
	self.rushTo = pos
end

local function Alive(ent) return IsValid(ent) and ent:Health() > 0 end

-- Armed and freed (following a rescuer): a look now and then, and a shot at
-- RED in sight within range; its first shot reveals it.
function ENT:Defend()
	if not IsValid(self.leader) then return end
	local now = CurTime()
	if now >= (self.wsNextLook or 0) then
		self.wsNextLook = now + LOOK_INTERVAL
		self:VisionTell(self.nsVision:Prune(Alive, self.nsBetter))
		self:VisionUpdate(now)
	end
	local enemy = self:GetEnemy()
	if enemy and self.nsVision:Visible(enemy) and self.nsVision:Recognized(enemy, now) and self:GetRangeTo(enemy) <= DEFEND_RANGE then
		local weapon = self:GetActiveWeapon()
		local magazine = self.nsMagazines[weapon]
		local before = magazine and magazine:Rounds()
		self:RangeAttack(enemy, weapon)
		if magazine and magazine:Rounds() ~= before and not self.revealed then
			self.revealed = true
			self:SetNoTarget(false)
		end
	end
end

-- Whom the hostage follows (an entity), or nil.
function ENT:SetLeader(leader)
	self.leader = leader
end

-- Led into the rescue zone: out of the round, standing where it was.
function ENT:Rescued()
	self.rescued = true
	self.leader = nil
	self.NSTarget = nil
	self.NSFrozen = true
	self:SetNoDraw(true)
	self:SetNotSolid(true)
end

-- Glass within GLASS_REACH of its waist, whichever way it faces (wedged at a
-- sill, it is not always facing the pane), broken where it is nearest.
function ENT:BreakGlass()
	local waist = self:GetPos() + Vector(0, 0, 36)
	for _, glass in ipairs(ents.FindInSphere(waist, GLASS_REACH)) do
		if glass:GetClass() == "func_breakable_surf" then
			local at = glass:NearestPoint(waist)
			local dir = at - waist
			dir.z = 0
			dir:Normalize()
			local tr = util.TraceLine({ start = waist, endpos = at + dir * 4, mask = MASK_PLAYERSOLID, filter = self })
			if tr.Entity == glass then
				local dmg = DamageInfo()
				dmg:SetDamage(GLASS_DAMAGE)
				dmg:SetDamageType(DMG_CLUB)
				dmg:SetAttacker(self)
				dmg:SetInflictor(self)
				dmg:SetDamagePosition(tr.HitPos)
				dmg:SetDamageForce(dir * GLASS_DAMAGE)
				glass:DispatchTraceAttack(dmg, tr, dir)
			end
		end
	end
end

-- Its one behaviour: armed, defending itself as it goes; to a pistol it was
-- told to rush for; else after its rescuer, to FOLLOW_GAP of them; else it
-- stands.
function ENT:IntentionUpdate()
	if self.rescued then
		self.NSTarget = nil
		return
	end
	if self.armed then self:Defend() end
	if self.rushTo then
		self.NSTarget = self.rushTo
		self:BreakGlass()
		self:NSSteer()
		return
	end
	local leader = self.leader
	if not IsValid(leader) or self:GetPos():Distance(leader:GetPos()) <= FOLLOW_GAP then
		self.NSTarget = nil
		return
	end
	self.NSTarget = leader:GetPos()
	self:BreakGlass()
	self:NSSteer()
end
