-- An in-memory foundation.spells.caster for spell tests: a fake clock, a
-- scripted random source, fake targets (the owner among them), scripted
-- traces, and a log of every effect a spell asked for. It implements every
-- name in foundation.spells.caster.METHODS (spells_cast_test checks that).
local FakeActor = dofile("tests/fake_actor.lua")

local V = FakeActor.Vector

local Fake = {
	Vector = V,
	Clock = FakeActor.Clock,
	Random = FakeActor.Random,
}

local CENTER_HEIGHT, EYE_HEIGHT = 36, 64

-- A player or NPC the caster port hands out as an opaque handle.
function Fake.Target(t)
	local target = {
		name = t.name or "target",
		team = t.team,
		origin = t.origin or V(0, 0, 0),
		alive = t.alive ~= false,
		player = t.player ~= false,
		health = t.health or 100,
		maxHealth = t.maxHealth or 300,
		velocity = t.velocity or V(0, 0, 0),
		onGround = t.onGround ~= false,
		invulnerable = t.invulnerable == true,
		conds = t.conds or {},
	}
	return target
end

local Caster = {}
Caster.__index = Caster

-- t = { owner, targets (the owner is added), clock, random, forward, right,
-- up, shoot (the shoot position), hull(from, to) -> trace, line(from, to)
-- -> trace, wall(from, to) -> blocked, fits(pos) -> bool }.
function Fake.Caster(t)
	local targets = { t.owner }
	for _, target in ipairs(t.targets or {}) do targets[#targets + 1] = target end
	return setmetatable({
		owner = t.owner,
		targets = targets,
		clock = t.clock or Fake.Clock(0),
		random = t.random or Fake.Random({ 0.5 }),
		forward = t.forward or V(1, 0, 0),
		right = t.right or V(0, -1, 0),
		up = t.up or V(0, 0, 1),
		shoot = t.shoot or t.owner.origin + V(0, 0, EYE_HEIGHT),
		hull = t.hull,
		line = t.line,
		wall = t.wall,
		fits = t.fits,
		log = {},
		launched = 0,
	}, Caster)
end

function Caster:Record(kind, entry)
	entry.kind = kind
	self.log[#self.log + 1] = entry
	return entry
end

-- Every logged call of one kind, in order.
function Caster:Calls(kind)
	local found = {}
	for _, entry in ipairs(self.log) do
		if entry.kind == kind then found[#found + 1] = entry end
	end
	return found
end

-- time, chance, vectors
function Caster:Now() return self.clock:Now() end
function Caster:RandomFloat(lo, hi) return self.random:Float(lo, hi) end
function Caster:RandomInt(lo, hi) return self.random:Int(lo, hi) end
function Caster:Vector(x, y, z) return V(x, y, z) end

-- who is who
function Caster:Owner() return self.owner end
function Caster:TeamOf(t) return t.team end
function Caster:IsAlive(t) return t.alive end
function Caster:IsPlayer(t) return t.player end
function Caster:IsOnGround(t) return t.onGround end
function Caster:Origin(t) return t.origin end
function Caster:Center(t) return t.origin + V(0, 0, CENTER_HEIGHT) end
function Caster:EyePosition(t) return t.origin + V(0, 0, EYE_HEIGHT) end
function Caster:InCond(t, cond) return t.conds[cond] ~= nil end
function Caster:IsInvulnerable(t) return t.invulnerable end

-- aim
function Caster:ShootPosition() return self.shoot end
function Caster:EyeVectors() return self.forward, self.right, self.up end

-- the world
function Caster:TraceHull(from, to, mins, maxs)
	self:Record("TraceHull", {
		from = from,
		to = to,
		mins = mins,
		maxs = maxs,
	})
	if self.hull then return self.hull(from, to) end
	return {
		startSolid = false,
		endPos = to,
	}
end

function Caster:TraceLine(from, to)
	if self.line then return self.line(from, to) end
	return {
		hit = false,
		endPos = to,
		normal = V(0, 0, 0),
	}
end

function Caster:IsVisible(from, to)
	return not (self.wall and self.wall(from, to))
end

function Caster:Fits(t, pos)
	if self.fits then return self.fits(pos) end
	return true
end

function Caster:EntitiesInSphere(center, radius)
	local found = {}
	for _, target in ipairs(self.targets) do
		if (target.origin - center):Length() <= radius then found[#found + 1] = target end
	end
	return found
end

-- effects
function Caster:Heal(t, amount)
	t.health = math.min(t.maxHealth, t.health + amount)
	self:Record("Heal", {
		target = t,
		amount = amount,
	})
end

function Caster:AddCond(t, cond, duration)
	t.conds[cond] = duration
	self:Record("AddCond", {
		target = t,
		cond = cond,
		duration = duration,
	})
end

function Caster:Stun(t, duration, reduction)
	self:Record("Stun", {
		target = t,
		duration = duration,
		reduction = reduction,
	})
end

function Caster:GetVelocity(t) return t.velocity end

function Caster:SetVelocity(t, v)
	t.velocity = v
	self:Record("SetVelocity", {
		target = t,
		velocity = v,
	})
end

function Caster:Push(t, v)
	t.velocity = t.velocity + v
	self:Record("Push", {
		target = t,
		impulse = v,
	})
end

function Caster:Damage(t, amount, dmgType, inflictor)
	self:Record("Damage", {
		target = t,
		amount = amount,
		dmgType = dmgType,
		inflictor = inflictor,
	})
end

function Caster:Explode(config)
	self:Record("Explode", { config = config })
end

function Caster:LaunchProjectile(class, config)
	self.launched = self.launched + 1
	return self:Record("LaunchProjectile", {
		class = class,
		config = config,
	})
end

function Caster:SpawnNPC(class, config, pos)
	return self:Record("SpawnNPC", {
		class = class,
		config = config,
		pos = pos,
	})
end

function Caster:Spawn(class, config, pos)
	return self:Record("Spawn", {
		class = class,
		config = config,
		pos = pos,
	})
end

function Caster:Teleport(t, pos)
	t.origin = pos
	self:Record("Teleport", {
		target = t,
		pos = pos,
	})
end

function Caster:ScreenFade(t)
	self:Record("ScreenFade", { target = t })
end

function Caster:Particle(name, pos)
	self:Record("Particle", {
		name = name,
		pos = pos,
	})
end

function Caster:AttachParticle(name, t)
	self:Record("AttachParticle", {
		name = name,
		target = t,
	})
end

function Caster:Tracer(name, from, to)
	self:Record("Tracer", {
		name = name,
		from = from,
		to = to,
	})
end

function Caster:EmitSound(name, source)
	self:Record("EmitSound", {
		name = name,
		source = source,
	})
end

return Fake
