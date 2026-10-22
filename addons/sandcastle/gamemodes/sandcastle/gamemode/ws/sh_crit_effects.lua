-- How crits look as they fly (foundation.combat.crit_effects): its
-- particles precached on both realms, since the server names them to
-- clients (a crit bullet's tracer, ws/sv_hits.lua), and a crit-boosted
-- shooter's rocket, bolt or grenade trailing TF2's crit trail, seen by
-- everyone, as C_TFProjectile_Rocket::CreateTrails shows a crit rocket.
local Crit = WS.require("foundation.combat.crit_effects")
local P = WS.PlayerRules

for _, path in ipairs(Crit.FILES) do game.AddParticles(path) end
for _, name in ipairs(Crit.PARTICLES) do PrecacheParticleSystem(name) end

if CLIENT then return end

-- Who fired a projectile: HL2's rocket and bolt are owned by their
-- shooter, a frag by its thrower.
local function Shooter(projectile)
	local owner = projectile:GetOwner()
	if IsValid(owner) then return owner end
	return projectile:GetInternalVariable("m_hThrower")
end

hook.Add("OnEntityCreated", "ws_crit_effects", function(ent)
	if not Crit.TRAILS[ent:GetClass()] then return end
	-- its shooter is set once it has spawned
	timer.Simple(0, function()
		if not IsValid(ent) then return end
		local shooter = Shooter(ent)
		if not (IsValid(shooter) and P.CritBoosted(WS.ConditionsOf(shooter), CurTime())) then return end
		ParticleEffectAttach(Crit.Trail(ent:GetClass(), WS.TeamNumber(shooter)), PATTACH_ABSORIGIN_FOLLOW, ent, 0)
	end)
end)
