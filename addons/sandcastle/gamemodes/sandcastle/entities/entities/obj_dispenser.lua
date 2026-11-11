-- obj_dispenser (CObjectDispenser, tf_obj_dispenser.cpp), level 1: built, it heals its team's living
-- bodies within its range that it sees (gameplay.buildings' Serves, Dispensed) and gives its team's
-- players ammo for the weapon in hand every interval (AmmoGiven).
AddCSLuaFile ()

ENT.Base = "base_obj"
ENT.Kind = "dispenser"
ENT.Model = "models/buildables/dispenser.mdl"
-- TF2's DISPENSER_MODEL_BUILDING: the model holding its build animation.
ENT.BuildModel = "models/buildables/dispenser_light.mdl"
-- TF2's DISPENSER_MINS and DISPENSER_MAXS: its models have no collision shape for a bullet to hit.
ENT.HullMins, ENT.HullMaxs = Vector (-20, -20, 0), Vector (20, 20, 55)
ENT.PrintName = "#TF_Object_Dispenser"
ENT.Spawnable = true
ENT.Category = "Sandcastle"

local Buildings = gameplay.buildings

local HEAL_SOUND = "weapons/dispenser_heal.wav"
local AMMO_SOUND = "weapons/dispenser_generate_metal.wav"
-- Where it looks from at those it serves.
local EYE_UP = Vector (0, 0, 40)

if SERVER then
	function ENT:ObjInitialize ()
		self.nextAmmo = 0
	end

	-- Its team's living bodies within its range that it sees.
	function ENT:Served ()
		local team, from, served = self:GetObjTeam (), self:GetPos () + EYE_UP, {}
		for _, ent in ipairs (ents.FindInSphere (self:WorldSpaceCenter (), Buildings.DISPENSER_RANGE)) do
			if (ent:IsPlayer () or ent:IsNPC () or ent:IsNextBot ()) and ent:Health () > 0 and Buildings.Serves (team, WS.TeamNumber (ent)) then
				local tr = util.TraceLine ({ start = from, endpos = ent:WorldSpaceCenter (), mask = MASK_SOLID_BRUSHONLY })
				if not tr.Hit then served [#served + 1] = ent end
			end
		end
		return served
	end

	-- A player's weapon in hand, topped up by its share of what the player may carry.
	local function GiveAmmo (ply)
		local weapon = ply:GetActiveWeapon ()
		if not IsValid (weapon) then return false end
		local ammo = weapon:GetPrimaryAmmoType ()
		if ammo < 0 then return false end
		local given = Buildings.AmmoGiven (ply:GetAmmoCount (ammo), game.GetAmmoMax (ammo))
		if given <= 0 then return false end
		ply:GiveAmmo (given, ammo, true)
		return true
	end

	function ENT:ObjThink ()
		local now, dt = CurTime (), FrameTime ()
		local ammoDue = now >= self.nextAmmo
		if ammoDue then self.nextAmmo = now + Buildings.DISPENSER_AMMO_INTERVAL end
		local healed, stocked = false, false
		for _, ent in ipairs (self:Served ()) do
			if ent:Health () < ent:GetMaxHealth () then
				-- whole points, its fractions carried over from tick to tick
				local carried = (ent.wsDispensed or 0) + Buildings.Dispensed (0, math.huge, dt)
				local whole = math.floor (carried)
				ent.wsDispensed = carried - whole
				if whole > 0 then
					ent:SetHealth (math.min (ent:Health () + whole, ent:GetMaxHealth ()))
					healed = true
				end
			end
			if ammoDue and ent:IsPlayer () and GiveAmmo (ent) then stocked = true end
		end
		if healed and not self.healing then self:EmitSound (HEAL_SOUND, 65) end
		self.healing = healed
		if stocked then self:EmitSound (AMMO_SOUND, 65) end
	end
end
