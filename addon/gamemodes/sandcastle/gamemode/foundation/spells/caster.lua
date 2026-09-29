-- The caster port: everything a spell may ask of the world, for one caster
-- (a player). The spells controller implements it; tests/fake_caster.lua
-- fakes it. Targets are opaque handles; vectors support + - * (by a number),
-- :Length(), :GetNormalized(), :Dot(v) and .x .y .z.
--
--   time, chance     Now(), RandomFloat(lo, hi), RandomInt(lo, hi), Vector(x, y, z)
--   who              Owner() (the caster), TeamOf(t), IsAlive(t), IsPlayer(t),
--                    IsOnGround(t), Origin(t), Center(t), EyePosition(t),
--                    InCond(t, cond), IsInvulnerable(t)
--   aim              ShootPosition(), EyeVectors() -> forward, right, up
--   world            TraceHull(from, to, mins, maxs) -> { startSolid, endPos }
--                    (solid world and props; players and NPCs pass),
--                    TraceLine(from, to) -> { hit, endPos, normal },
--                    IsVisible(from, to) (no world between the points),
--                    PlayerFits(t, pos) (t's hull is clear at pos),
--                    EntitiesInSphere(v, r) -> the players and NPCs within r
--   effects          Heal(t, n) (up to max health), AddCond(t, cond, d),
--                    Stun(t, d, reduction), GetVelocity(t), SetVelocity(t, v),
--                    Push(t, v) (adds velocity, off the ground),
--                    Damage(t, n, dmgType, inflictor), Explode(config)
--                    (a foundation.combat Explosion config, with attacker and
--                    inflictor), LaunchProjectile(class, config) -> handle,
--                    SpawnNPC(class, config, pos) -> handle,
--                    Spawn(class, config, pos) -> handle, Teleport(t, pos),
--                    ScreenFade(t), Particle(name, pos), AttachParticle(name, t),
--                    Tracer(name, from, to), EmitSound(name, source) (source
--                    nil: from the caster)
--
-- A launched projectile's config holds { spell (its index), position,
-- velocity, team } and what its spell adds; the projectile binds to a Shot
-- and calls its Impact when it lands.
module(...)

-- Source's damage type bits.
DMG_BURN = 8
DMG_BLAST = 64

METHODS = {
	"Now",
	"RandomFloat",
	"RandomInt",
	"Vector",
	"Owner",
	"TeamOf",
	"IsAlive",
	"IsPlayer",
	"IsOnGround",
	"Origin",
	"Center",
	"EyePosition",
	"InCond",
	"IsInvulnerable",
	"ShootPosition",
	"EyeVectors",
	"TraceHull",
	"TraceLine",
	"IsVisible",
	"PlayerFits",
	"EntitiesInSphere",
	"Heal",
	"AddCond",
	"Stun",
	"GetVelocity",
	"SetVelocity",
	"Push",
	"Damage",
	"Explode",
	"LaunchProjectile",
	"SpawnNPC",
	"Spawn",
	"Teleport",
	"ScreenFade",
	"Particle",
	"AttachParticle",
	"Tracer",
	"EmitSound",
}
