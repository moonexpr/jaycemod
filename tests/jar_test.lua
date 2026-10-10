local T = dofile("tests/harness.lua")
local Jar = T.require("foundation.projectile.jar")
local Teams = T.require("foundation.teams")

-- A player near the splash, as the jar's binding sees them.
local function Near(t)
	t = t or {}
	return {
		team = t.team or Teams.RED,
		alive = t.alive ~= false,
		distance = t.distance or 100,
		wallBetween = t.wallBetween or false,
		invulnerable = t.invulnerable or false,
		phased = t.phased or false,
		wet = t.wet or false,
	}
end

-- JarExplode
T.test("a jar drenches every living enemy within its radius with nothing solid between", function()
	T.defined(Jar.RADIUS, "JAR_EXPLODE_RADIUS")
	T.defined(Jar.URINE_TIME, "Jar.URINE_TIME")
	T.eq(Jar.Drenches(Near(), Teams.UNASSIGNED), true, "the wheel's jar is nobody's: everyone")
	T.eq(Jar.Drenches(Near({ team = Teams.BLUE }), Teams.RED), true, "an enemy")
	T.eq(Jar.Drenches(Near({ team = Teams.RED }), Teams.RED), false, "not a teammate")
	T.eq(Jar.Drenches(Near({ distance = Jar.RADIUS + 1 }), Teams.UNASSIGNED), false, "too far")
	T.eq(Jar.Drenches(Near({ alive = false }), Teams.UNASSIGNED), false, "the dead")
	T.eq(Jar.Drenches(Near({ wallBetween = true }), Teams.UNASSIGNED), false, "behind the world")
	T.eq(Jar.Drenches(Near({ invulnerable = true }), Teams.UNASSIGNED), false, "ubered")
	T.eq(Jar.Drenches(Near({ phased = true }), Teams.UNASSIGNED), false, "phased")
	T.eq(Jar.Drenches(Near({ wet = true }), Teams.UNASSIGNED), false, "in water (CanGetWet)")
end)

T.test("the jar's look and sound are TF2's", function()
	T.eq(Jar.MODEL, "models/weapons/c_models/urinejar.mdl", "TF_WEAPON_PEEJAR_MODEL")
	T.eq(Jar.IMPACT_PARTICLE, "peejar_impact", "the splash")
	T.eq(Jar.EXPLODE_SOUND, "Jar.Explode", "the smash")
end)

T.finish()
