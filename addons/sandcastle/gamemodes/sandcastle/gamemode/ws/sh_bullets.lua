-- Every bullet fired, on both realms, passes WS.BulletSteps
-- (foundation.combat.bullet_steps) in order: the one EntityFireBullets hook
-- that changes shots. WS.FireBulletsAgain fires bullets a step made from a
-- shot (the fixed spread's pellets) past the steps, which have seen it.
local Steps = WS.require("foundation.combat.bullet_steps")

WS.BulletSteps = WS.BulletSteps or Steps.New()

local again = false

function WS.FireBulletsAgain(ent, data)
	again = true
	ent:FireBullets(data)
	again = false
end

hook.Add("EntityFireBullets", "ws_bullets", function(ent, data)
	if again then return end
	return WS.BulletSteps:Run(ent, data)
end)
