-- Entities put where a test needs them, and players put in a condition, by hand.
--   ENTITY:Teleport(target[, facingTowards]) puts the entity before target, along the way target
--   faces, the two clear of each other (sandcastle_dev_place), turned to face it (facingTowards,
--   true unless false) or the way it faces; its own hull swept out from target, so a wall stops
--   it short (where the sweep starts inside something, it is put at the spot unswept). Its
--   motion is stopped. Returns where it stands and its yaw.
--   PLAYER:AddCondition(cond[, timeout]) puts the player in a TF2 condition (WS.AddCondition) for
--   timeout seconds, -1 (the default) for good; PLAYER:RemoveCondition(cond) takes it away. cond
--   is its number or its name (URINE, TF_COND_URINE); one the game has not is refused.
local Place = dev.require ("sandcastle_dev_place")
local Condition = dev.require ("sandcastle_dev_condition")
local ENTITY = FindMetaTable ("Entity")
local PLAYER = FindMetaTable ("Player")

-- A step off the floor for the sweep, so the floor itself does not stop it.
local LIFT = Vector (0, 0, 1)

local function Facing (ent)
	return ent:IsPlayer () and ent:EyeAngles ().y or ent:GetAngles ().y
end

local function Stop (ent)
	if ent:IsPlayer () then return ent:SetVelocity (-ent:GetVelocity ()) end
	if ent.loco then ent.loco:SetVelocity (vector_origin) end
	local phys = ent:GetPhysicsObject ()
	if IsValid (phys) then phys:SetVelocity (vector_origin) end
end

function ENTITY:Teleport (target, facingTowards)
	if not IsValid (target) then dev.Fail ("Teleport: no entity to stand before") end
	if target == self then dev.Fail ("Teleport: an entity cannot stand before itself") end
	local from, facing = target:GetPos (), Facing (target)
	local mins, maxs = self:OBBMins (), self:OBBMaxs ()
	local spot = Place.Before (from, facing, Place.Reach (target:OBBMins (), target:OBBMaxs ()), Place.Reach (mins, maxs))
	local swept = util.TraceHull (
		{
			start = from + LIFT,
			endpos = Vector (spot.x, spot.y, spot.z) + LIFT,
			mins = mins,
			maxs = maxs,
			mask = MASK_PLAYERSOLID,
			filter = { self, target }
		}
	)
	local pos = swept.StartSolid and Vector (spot.x, spot.y, spot.z) or swept.HitPos - LIFT
	local yaw = Place.Yaw (facing, facingTowards ~= false)
	self:SetPos (pos)
	if self:IsPlayer () then self:SetEyeAngles (Angle (0, yaw, 0)) else self:SetAngles (Angle (0, yaw, 0)) end
	Stop (self)
	return pos, yaw
end

function PLAYER:AddCondition (value, timeout)
	local cond = Condition.Parse (WS.PlayerRules.COND, value)
	if not cond then dev.Fail ("no condition " .. tostring (value)) end
	WS.AddCondition (self, cond, timeout or WS.PlayerRules.PERMANENT)
end

function PLAYER:RemoveCondition (value)
	local cond = Condition.Parse (WS.PlayerRules.COND, value)
	if not cond then dev.Fail ("no condition " .. tostring (value)) end
	WS.RemoveCondition (self, cond)
end
