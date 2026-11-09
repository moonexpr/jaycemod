-- Resupply and the ammo pack a dying player drops.
local P = WS.PlayerRules

-- CTFPlayer::Regenerate(true): full health (an overheal is kept), every
-- weapon's clips and reserve refilled, fire and the debuffs removed.
function WS.RegeneratePlayer(ply)
	ply:SetHealth(P.RegenerateHealth(ply:Health(), ply:GetMaxHealth()))
	WS.ClearConditionsOnRegenerate(ply)
	for _, wep in ipairs(ply:GetWeapons()) do
		if wep:GetMaxClip1() > 0 then wep:SetClip1(wep:GetMaxClip1()) end
		if wep:GetMaxClip2() > 0 then wep:SetClip2(wep:GetMaxClip2()) end
	end
	WS.GiveAmmoFraction(ply, 1.0)
end

-- tf_weapon_ragdoll_velocity_min/max and maxspeed.
local THROW_MIN, THROW_MAX, THROW_CAP = 100, 150, 300

-- CTFPlayer::DropAmmoPack / CTFAmmoPack::InitAmmoPack: a player with a
-- weapon drops a medium ammo pack, thrown a little from where they died.
function WS.DropAmmoPack(ply)
	if #ply:GetWeapons() == 0 then return end
	local pack = ents.Create("tf_ammo_pack")
	pack:SetPos(ply:WorldSpaceCenter())
	pack:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	pack:SetOwner(ply)
	pack:Spawn()
	local ang = ply:EyeAngles()
	local impulse = (ang:Up() * math.Rand(-0.25, 0.25) + ang:Right() * math.Rand(-0.25, 0.25)):GetNormalized()
	impulse = impulse * math.Rand(THROW_MIN, THROW_MAX) + ply:GetVelocity()
	if impulse:Length() > THROW_CAP then impulse = impulse:GetNormalized() * THROW_CAP end
	local phys = pack:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetMass(25)
		phys:SetVelocityInstantaneous(impulse)
		phys:AddAngleVelocity(Vector(0, math.Rand(0, 100), 0))
	end
end
