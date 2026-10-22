local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local Mimic = T.require("games.gameplay.combat.weapon_mimic")
local Projectile = T.require("games.gameplay.projectile")
local Pipe = T.require("games.gameplay.projectile.pipe")
local Rocket = T.require("games.gameplay.projectile.rocket")
local Teams = T.require("games.gameplay.teams")

local V = Fake.Vector
local EPSILON = 1e-9

-- Aimed down +x, as angles 0 0 0 give.
local AIM = {
	forward = V(1, 0, 0),
	right = V(0, -1, 0),
	up = V(0, 0, 1),
}

-- A scripted random source that also notes the ranges it was asked for.
local function Script(floats, ints)
	local s = {
		asked = {},
	}
	function s.Float(lo, hi)
		s.asked[#s.asked + 1] = lo .. ".." .. hi
		return table.remove(floats, 1)
	end
	function s.Int(lo, hi)
		s.asked[#s.asked + 1] = "int " .. lo .. ".." .. hi
		return table.remove(ints or {}, 1)
	end
	return s
end

-- pl_terror_event's two mimics.
local function Rawkets(extra)
	local config = {
		weaponType = Mimic.WEAPON_STANDARD_ROCKET,
		speedMin = 500,
		speedMax = 600,
		spreadAngle = 0,
		damage = 60,
		splashRadius = 50,
		crits = true,
		modelScale = 1,
	}
	for k, v in pairs(extra or {}) do config[k] = v end
	return Mimic.New(config)
end

local function Grenades(extra)
	local config = {
		weaponType = Mimic.WEAPON_STANDARD_GRENADE,
		speedMin = 1000,
		speedMax = 1200,
		spreadAngle = 30,
		damage = 60,
		splashRadius = 50,
		crits = true,
		modelScale = 1.2,
	}
	for k, v in pairs(extra or {}) do config[k] = v end
	return Mimic.New(config)
end

local function Degrees(a, b)
	return math.deg(math.acos(math.min(1, a:Dot(b) / (a:Length() * b:Length()))))
end

T.test("with no spread a rocket flies straight along the mimic at a speed from the range", function()
	local random = Script({ 550 })
	local shot = Rawkets():Shot(AIM, random.Float, random.Int)
	T.eq(shot.class, Mimic.ROCKET_CLASS, "class")
	T.eq(table.concat(random.asked, ","), "500..600", "only the speed is drawn")
	T.eq(shot.config.velocity, V(550, 0, 0), "velocity")
end)

T.test("a rocket is a crit BLU rocket with the mimic's damage and TF2's own radius", function()
	local random = Script({ 550 })
	local config = Rawkets():Shot(AIM, random.Float, random.Int).config
	T.eq(config.damage, 60, "damage")
	T.eq(config.crit, true, "crit")
	T.eq(config.team, Teams.BLUE, "ChangeTeam(TF_TEAM_BLUE)")
	T.eq(config.radius, nil, "FireRocket leaves the radius alone")
	T.eq(config.model, nil, "the rocket's own model")
end)

T.test("ModelOverride replaces the projectile's model", function()
	local model = "models/props_halloween/pumpkin_explode.mdl"
	local random = Script({ 550 })
	T.eq(Rawkets({ modelOverride = model }):Shot(AIM, random.Float, random.Int).config.model, model, "model")
end)

T.test("spread turns the shot off the aim by up to half the angle, around a random axis", function()
	local random = Script({ 15, 90, 1100 }, { 0 })
	local shot = Grenades():Shot(AIM, random.Float, random.Int)
	T.eq(random.asked[1], "-15..15", "half the spread about up")
	T.eq(random.asked[2], "-180..180", "then any turn about forward")
	T.eq(random.asked[3], "1000..1200", "then the speed")
	local v = shot.config.velocity
	T.near(v:Length(), 1100, EPSILON, "speed")
	T.near(Degrees(v, AIM.forward), 15, EPSILON, "off the aim")
	T.near(v.y, 0, EPSILON, "a quarter turn about forward points it up")
	T.eq(v.z > 0, true, "up")
end)

T.test("the spread stays inside its cone for any draw", function()
	for _, draw in ipairs({ { -15, -180 }, { 15, 180 }, { 7, -45 }, { 0, 33 } }) do
		local random = Script({ draw[1], draw[2], 1000 }, { 0 })
		local v = Grenades():Shot(AIM, random.Float, random.Int).config.velocity
		T.near(Degrees(v, AIM.forward), math.abs(draw[1]), 1e-6, "angle for " .. draw[1] .. "," .. draw[2])
	end
end)

T.test("a grenade is a 2 s BLU pipe with the mimic's damage, splash radius and scale", function()
	local random = Script({ 0, 0, 1000 }, { -300 })
	local shot = Grenades():Shot(AIM, random.Float, random.Int)
	local config = shot.config
	T.eq(shot.class, Mimic.PIPE_CLASS, "class")
	T.eq(config.fuse, Mimic.GRENADE_FUSE, "SetDetonateTimerLength(2)")
	T.eq(config.explodeOnTouch, false, "it passes through players")
	T.eq(config.damage, 60, "damage")
	T.eq(config.radius, 50, "SplashRadius")
	T.eq(config.crit, true, "crit")
	T.eq(config.team, Teams.BLUE, "team")
	T.eq(config.skin, Mimic.GRENADE_SKIN, "BLU skin")
	T.eq(config.scale, 1.2, "ModelScale")
	T.eq(random.asked[4], "int -1200..1200", "spin drawn last")
	T.eq(config.spin.x, Mimic.GRENADE_SPIN, "spin")
	T.eq(config.spin.y, -300, "tumble")
	T.eq(config.spin.z, 0, "no roll")
end)

T.test("only rockets and grenades fire; arrows and stickies do not", function()
	T.eq(Rawkets():Fires(), true, "rocket")
	T.eq(Grenades():Fires(), true, "grenade")
	T.eq(Rawkets({ weaponType = Mimic.WEAPON_STANDARD_ARROW }):Fires(), false, "arrow")
	T.eq(Rawkets({ weaponType = Mimic.WEAPON_STICKY_GRENADE }):Fires(), false, "sticky")
end)

T.test("FireMultiple fires at least once, and a negative count counts", function()
	T.eq(Mimic.FireCount(0), 1, "zero")
	T.eq(Mimic.FireCount(3), 3, "three")
	T.eq(Mimic.FireCount(-2), 2, "abs")
end)

local function NewPipe(now)
	return Projectile.New(Pipe, {
		fuse = Mimic.GRENADE_FUSE,
		explodeOnTouch = false,
		damage = 60,
		crit = true,
		team = Teams.BLUE,
		attacker = "mimic",
		radius = 50,
	}, now)
end

T.test("a pipe bounces off whatever it touches and goes off when its fuse ends", function()
	local pipe = NewPipe(0)
	T.eq(pipe:Touch({ world = false, enemy = true }), Projectile.BOUNCE, "players do not set it off")
	T.eq(pipe:Touch({ world = true, enemy = false }), Projectile.BOUNCE, "walls")
	T.eq(pipe:Tick(Mimic.GRENADE_FUSE / 2), Projectile.NONE, "burning")
	T.eq(pipe:Tick(Mimic.GRENADE_FUSE), Projectile.DETONATE, "fuse")
end)

T.test("a pipe's blast is its damage, radius, team and crit, credited to the mimic", function()
	local pipe = NewPipe(0)
	local blast = Pipe.Blast(pipe.state, V(1, 2, 3))
	T.eq(blast.origin, V(1, 2, 3), "origin")
	T.eq(blast.damage, 60, "damage")
	T.eq(blast.radius, 50, "radius")
	T.eq(blast.attackerTeam, Teams.BLUE, "team")
	T.eq(blast.attacker, "mimic", "attacker")
	T.eq(blast.crit, true, "crit")
	T.eq(blast.halfFalloff, false, "no half falloff")
	T.eq(Pipe.GRAVITY > 0, true, "it arcs")
	T.eq(Rocket.ROCKET_RADIUS ~= 50, true, "rockets keep their own radius")
end)

T.finish()
