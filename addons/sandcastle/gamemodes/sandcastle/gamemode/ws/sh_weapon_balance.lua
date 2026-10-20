-- The weapon balance's shots (foundation.combat.weapon_balance), on both
-- realms so a player's own shots predict: a balanced weapon's cone is its
-- own, and it fires no faster than its interval. A player's attack button
-- is held back until the weapon may fire again (HL2's pistol refires on
-- every click, whatever its next attack time says); a soldier's DrGBase
-- gun waits as long as its own delay or the interval, whichever is longer.
-- Its hits are ws/sv_hits.lua's.
local Balance = WS.require("foundation.combat.weapon_balance")
local BulletSteps = WS.require("foundation.combat.bullet_steps")

local function Held(shooter)
	if not shooter.GetActiveWeapon then return nil end
	local weapon = shooter:GetActiveWeapon()
	if not IsValid(weapon) then return nil end
	return weapon
end

WS.BulletSteps:Add("ws_weapon_balance", BulletSteps.BALANCE, function(ent, data)
	local shooter = ent:IsWeapon() and ent:GetOwner() or ent
	if not IsValid(shooter) then return end
	local weapon = Held(shooter)
	if weapon == nil then return end
	local class, now = weapon:GetClass(), CurTime()
	local next = Balance.NextShot(class, now)
	if next ~= nil then
		weapon.WSFiredAt = now
		if not shooter:IsPlayer() then weapon._DrGBaseNextShoot = math.max(weapon._DrGBaseNextShoot or 0, next) end
	end
	local spread = Balance.Spread(class)
	if spread == nil then return end
	data.Spread = Vector(spread, spread, 0)
	return BulletSteps.CHANGED
end)

hook.Add("StartCommand", "ws_weapon_balance", function(ply, cmd)
	if not cmd:KeyDown(IN_ATTACK) then return end
	local weapon = Held(ply)
	if weapon ~= nil and not Balance.CanFire(weapon:GetClass(), weapon.WSFiredAt, CurTime()) then
		cmd:RemoveKey(IN_ATTACK)
	end
end)
