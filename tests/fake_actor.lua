-- An in-memory foundation.npc.actor for model tests: a fake clock, a
-- scripted random source, fake targets, and a log of every effect the model
-- asked for. It implements every name in foundation.npc.actor.METHODS
-- (npc_test checks that).
--
-- Given its variant (Fake.Actor{ variant = Zombie }), the actor refuses a
-- particle system the variant does not list in PARTICLES: the npc
-- controller precaches only those, and the engine draws nothing for a
-- name it has not precached.
local Fake = {}

-- Vec: the vector the port hands out, with the operations models use.
local Vec = {}
Vec.__index = Vec

local function V(x, y, z)
	return setmetatable({
		x = x,
		y = y,
		z = z,
	}, Vec)
end
Fake.Vector = V

function Vec.__add(a, b) return V(a.x + b.x, a.y + b.y, a.z + b.z) end
function Vec.__sub(a, b) return V(a.x - b.x, a.y - b.y, a.z - b.z) end
function Vec.__unm(a) return V(-a.x, -a.y, -a.z) end
function Vec.__eq(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
function Vec.__tostring(a) return string.format("(%g, %g, %g)", a.x, a.y, a.z) end

function Vec.__mul(a, b)
	if type(a) == "number" then return V(a * b.x, a * b.y, a * b.z) end
	return V(a.x * b, a.y * b, a.z * b)
end

function Vec:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function Vec:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
function Vec:Dot(v) return self.x * v.x + self.y * v.y + self.z * v.z end

function Vec:GetNormalized()
	local length = self:Length()
	if length == 0 then return V(0, 0, 0) end
	return self * (1 / length)
end

function Fake.IsVec(v)
	return getmetatable(v) == Vec
end

-- Clock: Now() and Advance(dt).
local Clock = {}
Clock.__index = Clock

function Fake.Clock(now)
	return setmetatable({ now = now }, Clock)
end

function Clock:Now() return self.now end
function Clock:Advance(dt) self.now = self.now + dt end

-- Random: each draw takes the next scripted fraction in [0, 1] (the last one
-- repeats), so a test says where in each range a draw lands.
local Random = {}
Random.__index = Random

function Fake.Random(fractions)
	return setmetatable({
		fractions = fractions,
		next = 1,
	}, Random)
end

function Random:Fraction()
	local f = self.fractions[math.min(self.next, #self.fractions)]
	self.next = self.next + 1
	return f
end

function Random:Float(lo, hi) return lo + self:Fraction() * (hi - lo) end
function Random:Int(lo, hi) return math.min(hi, lo + math.floor(self:Fraction() * (hi - lo + 1))) end

-- A target: the opaque handle the port's target methods read.
local CENTER_HEIGHT, EYE_HEIGHT = 36, 64

function Fake.Target(t)
	local target = {
		origin = t.origin or V(0, 0, 0),
		alive = t.alive ~= false,
		valid = t.valid ~= false,
		velocity = t.velocity or V(0, 0, 0),
		maxHealth = t.maxHealth or 100,
		index = t.index or 0,
		onGround = t.onGround ~= false,
		onMesh = t.onMesh ~= false,
		visible = t.visible ~= false,
	}
	for k, v in pairs(t) do
		if target[k] == nil then target[k] = v end
	end
	return target
end

-- A path from NewPath(): records what the model asked of it.
local Path = {}
Path.__index = Path

local function NewPath(clock)
	return setmetatable({
		clock = clock,
		computes = 0,
		updates = 0,
		computedAt = nil,
		goal = nil,
		valid = false,
		lookAhead = nil,
	}, Path)
end

function Path:Compute(goal)
	self.computes = self.computes + 1
	self.computedAt = self.clock:Now()
	self.goal = goal
	self.valid = true
	return true
end

function Path:Update() self.updates = self.updates + 1 end
function Path:IsValid() return self.valid end
function Path:Invalidate() self.valid = false end
function Path:SetMinLookAheadDistance(d) self.lookAhead = d end
function Path:GetCurrentGoalPos() return self.goal end

-- The Path's age timer is an IntervalTimer: unstarted, it is very old.
local INTERVAL_UNSTARTED = 99999.9

function Path:GetAge()
	if self.computedAt == nil then return INTERVAL_UNSTARTED end
	return self.clock:Now() - self.computedAt
end

-- The actor.
local Actor = {}
Actor.__index = Actor

function Fake.Actor(t)
	t = t or {}
	return setmetatable({
		clock = t.clock or Fake.Clock(1),
		random = t.random or Fake.Random({ 0.5 }),
		alive = t.alive ~= false,
		origin = t.origin or V(0, 0, 0),
		yaw = t.yaw or 0,
		health = t.health or 100,
		maxHealth = t.maxHealth or 100,
		owner = t.owner,
		variant = t.variant,
		index = t.index or 1,
		shared = t.shared or {},
		calls = {},
		activity = nil,
		activityFinished = false,
		sequence = nil,
		sequenceFinished = false,
		gestures = {},
		pose = {},
		desiredSpeed = 0,
		attemptingToMove = false,
		groundSpeed = t.groundSpeed or 0,
		paths = {},
		removed = false,
	}, Actor)
end

-- The log: every effect and body change, in order.
function Actor:Record(name, ...)
	self.calls[#self.calls + 1] = {
		name = name,
		args = { ... },
	}
end

function Actor:Called(name)
	local found = {}
	for _, call in ipairs(self.calls) do
		if call.name == name then found[#found + 1] = call.args end
	end
	return found
end

-- time, chance
function Actor:Now() return self.clock:Now() end
function Actor:RandomFloat(lo, hi) return self.random:Float(lo, hi) end
function Actor:RandomInt(lo, hi) return self.random:Int(lo, hi) end

-- self
function Actor:IsAlive() return self.alive end
function Actor:GetAbsOrigin() return self.origin end
function Actor:SetAbsOrigin(v) self.origin = v end
function Actor:WorldSpaceCenter() return self.origin + V(0, 0, CENTER_HEIGHT) end
function Actor:EyePosition() return self.origin + V(0, 0, EYE_HEIGHT) end
function Actor:GetYaw() return self.yaw end
function Actor:SetYaw(deg) self.yaw = deg end
function Actor:GetHealth() return self.health end
function Actor:SetHealth(n) self.health = n end
function Actor:GetMaxHealth() return self.maxHealth end
function Actor:SetMaxHealth(n) self.maxHealth = n end
function Actor:GetOwnerEntity() return self.owner end
function Actor:GetEntIndex() return self.index end
function Actor:Shared() return self.shared end
function Actor:Vector(x, y, z) return V(x, y, z) end

function Actor:Remove()
	self.removed = true
	self:Record("Remove")
end

-- targets
function Actor:IsTargetValid(t) return t ~= nil and t.valid end
function Actor:IsTargetAlive(t) return t.alive end
function Actor:TargetOrigin(t) return t.origin end
function Actor:TargetCenter(t) return t.origin + V(0, 0, CENTER_HEIGHT) end
function Actor:TargetEyes(t) return t.origin + V(0, 0, EYE_HEIGHT) end
function Actor:TargetVelocity(t) return t.velocity end
function Actor:TargetMaxHealth(t) return t.maxHealth end
function Actor:TargetIndex(t) return t.index end
function Actor:IsTargetOnGround(t) return t.onGround end

-- relations: origin to origin, or to a Vec
function Actor:RangeTo(t)
	local point = Fake.IsVec(t) and t or t.origin
	return (point - self.origin):Length()
end

function Actor:IsRangeLessThan(t, r) return self:RangeTo(t) < r end
function Actor:IsRangeGreaterThan(t, r) return self:RangeTo(t) > r end
function Actor:IsLineOfSightClear(t, ignoreActors) return t.visible end
function Actor:IsOnNavMesh(t, tolerance2D) return t.onMesh end

-- body: activities are their names here
function Actor:Activity(name) return name end

function Actor:StartActivity(act)
	self.activity = act
	self.activityFinished = false
	self:Record("StartActivity", act)
	return true
end

function Actor:IsActivity(act) return self.activity == act end
function Actor:IsActivityFinished() return self.activityFinished end
function Actor:FinishActivity() self.activityFinished = true end

function Actor:PlaySequence(seq)
	self.sequence = seq
	self.sequenceFinished = false
	self:Record("PlaySequence", seq)
end

function Actor:IsSequenceFinished() return self.sequenceFinished end
function Actor:FinishSequence() self.sequenceFinished = true end

function Actor:AddGesture(act)
	self.gestures[act] = true
	self:Record("AddGesture", act)
end

function Actor:IsPlayingGesture(act) return self.gestures[act] == true end
function Actor:EndGesture(act) self.gestures[act] = nil end

function Actor:SetPoseParameter(name, v) self.pose[name] = v end
function Actor:SetSkin(n) self:Record("SetSkin", n) end
function Actor:SetModelScale(s) self:Record("SetModelScale", s) end
function Actor:SetBoneScale(bone, s) self:Record("SetBoneScale", bone, s) end
function Actor:AttachProp(model, bone) self:Record("AttachProp", model, bone) end

-- motion
function Actor:SetDesiredSpeed(u) self.desiredSpeed = u end
function Actor:FaceTowards(v) self:Record("FaceTowards", v) end
function Actor:IsAttemptingToMove() return self.attemptingToMove end
function Actor:GetGroundSpeed() return self.groundSpeed end

function Actor:Approach(v)
	self.attemptingToMove = true
	self:Record("Approach", v)
end

function Actor:NewPath()
	local path = NewPath(self.clock)
	self.paths[#self.paths + 1] = path
	return path
end

-- effects
function Actor:EmitSound(name) self:Record("EmitSound", name) end
local function Declares(variant, name)
	assert(type(variant.PARTICLES) == "table", "the variant has no PARTICLES list")
	for _, declared in ipairs(variant.PARTICLES) do
		if declared == name then return true end
	end
	return false
end

function Actor:DispatchParticleEffect(name, v)
	if self.variant and not Declares(self.variant, name) then
		error(string.format("particle system %q is not in the variant's PARTICLES", name), 2)
	end
	self:Record("DispatchParticleEffect", name, v)
end
function Actor:ScreenShake(v, amp, freq, dur, radius) self:Record("ScreenShake", v, amp, freq, dur, radius) end
function Actor:ApplyImpulse(t, v) self:Record("ApplyImpulse", t, v) end
function Actor:DealDamage(t, amount, dmgType, attacker) self:Record("DealDamage", t, amount, dmgType, attacker) end
function Actor:FireOutput(name, activator) self:Record("FireOutput", name, activator) end

function Actor:SpawnEntity(class, config, pos)
	self:Record("SpawnEntity", class, config, pos)
	return Fake.Target({ origin = pos })
end

return Fake
