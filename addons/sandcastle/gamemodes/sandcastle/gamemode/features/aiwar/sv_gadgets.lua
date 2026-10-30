-- Part of the AI war controller (sv.lua): the soldier port's gadgets
-- (sv_soldier.lua's Soldier:UseGadget), each kit's in its order.
local Map, Soldier = ...
local Punt = WS.require("features.aiwar.punt")
local ToVector = Map.ToVector
local Gestures = nextsoldier.gestures

-- Gadgets: what a kit's soldier throws, deploys or sends (the kit's
-- gadgets, first ready first): a frag grenade lobbed at p when nothing
-- solid stands between (every time asked), rolled or thrown by its distance
-- (nextsoldier.gestures' Throw); a floor turret set down toward
-- p (one per soldier, standing until it dies); a manhack sent from its hand
-- (one per soldier at a time, gone after MANHACK_LIFE); the gravity gun's
-- punt at the nearest enemy in its reach (features.aiwar.punt), a player's
-- punt in every way: HL2's hit from a gravity gun, which weapon_balance
-- makes its damage and a hard throw (ws/sv_hits.lua).
local GRENADE_FUSE, GRENADE_SPEED, GRENADE_MIN, GRENADE_MAX = 2.5, 700, 256, 1000
local TURRET_STEP, MANHACK_LIFE = 48, 45
local GADGET_CHEST = Vector(0, 0, 32)

local function ThrowAnimation(ent)
	if ent.AddGesture then ent:AddGesture(ACT_GMOD_GESTURE_ITEM_THROW) end
end

local GADGETS = {}

function GADGETS.grenade(soldier, target)
	local ent = soldier.ent
	local from = ent:EyePos()
	local distance = from:Distance(target)
	if distance < GRENADE_MIN or distance > GRENADE_MAX then return false end
	local tr = util.TraceLine({ start = from, endpos = target + GADGET_CHEST, mask = MASK_SOLID_BRUSHONLY })
	if tr.Hit then return false end
	local grenade = ents.Create("npc_grenade_frag")
	if not IsValid(grenade) then return false end
	grenade:SetPos(from + ent:GetForward() * 16)
	grenade:SetOwner(ent)
	grenade:Spawn()
	grenade:Activate()
	grenade:Fire("SetTimer", tostring(GRENADE_FUSE))
	-- a lob: across at GRENADE_SPEED, up enough to land on target
	local t = distance / GRENADE_SPEED
	local velocity = (target - from) / t
	velocity.z = velocity.z + 0.5 * physenv.GetGravity():Length() * t
	local phys = grenade:GetPhysicsObject()
	if IsValid(phys) then phys:SetVelocity(velocity) end
	soldier.controller:Gesture(ent, Gestures.Throw(distance), CurTime())
	soldier.controller:AddGadget(grenade, soldier, "grenade", CurTime() + GRENADE_FUSE + 1)
	return true
end

function GADGETS.turret(soldier, target)
	if soldier.controller:GadgetsOf(soldier, "turret") > 0 then return false end
	local ent = soldier.ent
	local dir = target - ent:GetPos()
	dir.z = 0
	if dir:IsZero() then return false end
	dir:Normalize()
	local pos = ent:GetPos() + dir * TURRET_STEP
	local tr = util.TraceHull({ start = pos + Vector(0, 0, 8), endpos = pos + Vector(0, 0, 8), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 64), mask = MASK_SOLID })
	if tr.Hit then return false end
	local turret = ents.Create("npc_turret_floor")
	if not IsValid(turret) then return false end
	turret:SetPos(pos)
	turret:SetAngles(Angle(0, dir:Angle().y, 0))
	turret:Spawn()
	turret:Activate()
	ThrowAnimation(ent)
	soldier.controller:AddGadget(turret, soldier, "turret")
	return true
end

function GADGETS.manhack(soldier)
	if soldier.controller:GadgetsOf(soldier, "manhack") > 0 then return false end
	local ent = soldier.ent
	local manhack = ents.Create("npc_manhack")
	if not IsValid(manhack) then return false end
	manhack:SetPos(ent:EyePos() + ent:GetForward() * 32)
	manhack:SetAngles(ent:GetAngles())
	manhack:Spawn()
	manhack:Activate()
	ThrowAnimation(ent)
	soldier.controller:AddGadget(manhack, soldier, "manhack", CurTime() + MANHACK_LIFE)
	return true
end

local PUNT_SOUND = "Weapon_PhysCannon.Launch"

-- The combatants within the punt's reach of ent: each { ent, distance,
-- enemy, clear } for Punt.Pick.
local function PuntCandidates(ent)
	local from, team = ent:EyePos(), WS.TeamNumber(ent)
	local enemy = WS.TeamRules.EnemyOf(team)
	local candidates = {}
	for _, other in ipairs(ents.FindInSphere(from, Punt.REACH)) do
		if other ~= ent and WS.Combatant(other) and other:Health() > 0 then
			local centre = other:WorldSpaceCenter()
			local tr = util.TraceLine({ start = from, endpos = centre, mask = MASK_SOLID_BRUSHONLY })
			candidates[#candidates + 1] = {
				ent = other,
				distance = from:Distance(centre),
				enemy = enemy ~= nil and WS.TeamNumber(other) == enemy,
				clear = not tr.Hit,
			}
		end
	end
	return candidates
end

-- CWeaponPhysCannon::PuntNonVPhysics: a hit of 1, DMG_CRUSH | DMG_PHYSGUN,
-- along the punt, from a gravity gun (weapon_balance reads its class off
-- the inflictor).
local function PuntHit(ent, victim)
	local dir = (victim:WorldSpaceCenter() - ent:EyePos()):GetNormalized()
	local cannon = ents.Create("weapon_physcannon")
	local dmg = DamageInfo()
	dmg:SetDamage(1)
	dmg:SetAttacker(ent)
	dmg:SetInflictor(IsValid(cannon) and cannon or ent)
	dmg:SetDamageType(bit.bor(DMG_CRUSH, DMG_PHYSGUN))
	dmg:SetDamageForce(dir)
	dmg:SetDamagePosition(victim:WorldSpaceCenter())
	victim:TakeDamageInfo(dmg)
	if IsValid(cannon) then cannon:Remove() end
end

function GADGETS.punt(soldier)
	local ent = soldier.ent
	local victim = Punt.Pick(PuntCandidates(ent))
	if not victim then return false end
	if ent.AddGesture then ent:AddGesture(ACT_HL2MP_GESTURE_RANGE_ATTACK_PHYSGUN) end
	ent:EmitSound(PUNT_SOUND)
	PuntHit(ent, victim.ent)
	return true
end

function Soldier:UseGadget(p)
	if not self.kit or not self.kit.gadgets or self.disarmed then return nil end
	local target = ToVector(p)
	for _, name in ipairs(self.kit.gadgets) do
		if GADGETS[name](self, target) then return name end
	end
	return nil
end
