-- The wheel feature's controller: the Wheel of Fate. It owns one
-- foundation.holiday.wheel model per wheel_of_doom entity, implements its
-- world port, ticks it, reapplies its effects to players as they spawn
-- (player_spawn, so after the spawn's own clearing), holds the gravity
-- multiplier, and networks the HUD's effect (wetsand_wheel_effect, _start
-- and _duration; the view draws it). Attributes go through the attributes
-- controller. Loaded by the first wheel_of_doom; it loads attributes.
local Wheel = WETSAND.require("foundation.holiday.wheel")

local WHEEL_CLASS = "wheel_of_doom"
local DANCER_CLASS = "merasmus_dancer"
local MERASMUS_CLASS = "merasmus"
local JAR_CLASS = "tf_projectile_jar"
local EFFECT = "wetsand_wheel_effect"
local EFFECT_START = "wetsand_wheel_effect_start"
local EFFECT_DURATION = "wetsand_wheel_effect_duration"
local NO_EFFECT = -1 -- ClearHalloweenEffectStatus
local THINK_HOOK = "wetsand_wheel"

PrecacheParticleSystem(Wheel.DANCER_POOF_PARTICLE)

local Controller = {
	attributes = WETSAND.Feature("attributes"),
	wheels = {}, -- wheel_of_doom entity -> { model, world }
	gravity = 1, -- CTFGameRules::m_flGravityMultiplier
}

-- SetGravityMultiplier: every player's gravity, and each spawning one's.
function Controller:SetGravity(m)
	self.gravity = m
	for _, ply in ipairs(player.GetAll()) do ply:SetGravity(m) end
end

-- SetHalloweenEffectStatus and ClearHalloweenEffectStatus.
function Controller:SetEffectStatus(skin, duration)
	SetGlobal2Int(EFFECT, skin)
	SetGlobal2Float(EFFECT_START, CurTime())
	SetGlobal2Float(EFFECT_DURATION, duration)
end

function Controller:ClearEffectStatus()
	SetGlobal2Int(EFFECT, NO_EFFECT)
end

local function Wheels(list, fn)
	for _, wheel in ipairs(list) do
		if IsValid(wheel) then fn(wheel) end
	end
end

-- The wheel's world port for one wheel entity.
local function World(controller, ent)
	local world = {}
	function world:Now() return CurTime() end
	function world:RandomInt(lo, hi) return math.random(lo, hi) end
	function world:RandomFloat(lo, hi) return math.Rand(lo, hi) end
	function world:Vector(x, y, z) return Vector(x, y, z) end
	function world:Players() return player.GetAll() end

	function world:LivingPlayers()
		local living = {}
		for _, ply in ipairs(player.GetAll()) do
			if ply:Alive() then living[#living + 1] = ply end
		end
		return living
	end

	function world:TeamOf(p) return p:Team() end
	function world:IsTargetValid(p) return IsValid(p) end
	function world:AddCond(p, cond, duration) WETSAND.AddCondition(p, cond, duration) end
	function world:RemoveCond(p, cond) WETSAND.RemoveCondition(p, cond) end
	function world:SetAttribute(p, name, value) controller.attributes:Give(p, name, value) end
	function world:RemoveAttribute(p, name) controller.attributes:Take(p, name) end
	function world:SetGravityMultiplier(m) controller:SetGravity(m) end

	function world:OtherWheels()
		local others = {}
		for _, wheel in ipairs(ents.FindByClass(WHEEL_CLASS)) do
			if wheel ~= ent then others[#others + 1] = wheel end
		end
		return others
	end

	function world:SetSkin(others, n)
		ent:SetSkin(n)
		Wheels(others, function(w) w:SetSkin(n) end)
	end

	function world:SetScale(others, s)
		ent:SetModelScale(s)
		Wheels(others, function(w) w:SetModelScale(s) end)
	end

	function world:SetVisible(on) ent:SetNoDraw(not on) end

	function world:GrowSpirals(others)
		ent:GrowSpiral()
		Wheels(others, function(w) w:GrowSpiral() end)
	end

	function world:ShrinkSpirals(others)
		ent:ShrinkSpiral()
		Wheels(others, function(w) w:ShrinkSpiral() end)
	end

	function world:BroadcastSound(name) WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, name) end

	-- Merasmus says it if he is about; otherwise everyone hears it.
	function world:Announce(name)
		local merasmus = ents.FindByClass(MERASMUS_CLASS)[1]
		if IsValid(merasmus) then
			merasmus:PlayHighPrioritySound(name)
		else
			WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, name)
		end
	end

	function world:SetEffectStatus(skin, duration) controller:SetEffectStatus(skin, duration) end
	function world:ClearEffectStatus() controller:ClearEffectStatus() end
	function world:FireOutput(name) ent:TriggerOutput(name, ent) end

	function world:DanceSpot(teamName, n)
		local spot = ents.FindByName(string.format(Wheel.DANCE_SPOT_FORMAT, teamName, n))[1]
		if not IsValid(spot) then return nil end
		return {
			pos = spot:GetPos(),
			yaw = spot:GetAngles().y,
		}
	end

	function world:Teleport(p, pos, yaw)
		local angles = Angle(0, yaw, 0)
		p:SetPos(pos)
		p:SetLocalVelocity(vector_origin)
		p:SetEyeAngles(angles)
	end

	function world:Taunt(p) p:DoAnimationEvent(ACT_GMOD_TAUNT_DANCE) end

	function world:SpawnDancer(pos, yaw)
		local dancer = ents.Create(DANCER_CLASS)
		dancer:SetPos(pos)
		dancer:SetAngles(Angle(0, yaw, 0))
		dancer:Spawn()
		return dancer
	end

	function world:DancerVanish(d)
		if IsValid(d) then d:Vanish() end
	end

	function world:DancerBlastOff(d)
		if IsValid(d) then d:BlastOff() end
	end

	-- The spawn_cloud brushes' world boxes (WorldAlignMins/Maxs about the
	-- origin).
	function world:CloudBoxes()
		local boxes = {}
		for _, cloud in ipairs(ents.FindByName(Wheel.CLOUD_NAME)) do
			local mins, maxs = cloud:WorldSpaceAABB()
			boxes[#boxes + 1] = {
				mins = mins,
				maxs = maxs,
			}
		end
		return boxes
	end

	-- A jar dropped, nobody's, spinning (its angular impulse in degrees a
	-- second about each axis).
	function world:DropJar(pos, spin)
		local jar = ents.Create(JAR_CLASS)
		jar:Configure({
			velocity = Vector(0, 0, 0),
			spin = Angle(spin.x, spin.y, spin.z),
			team = WETSAND.TEAM_UNASSIGNED,
		})
		jar:SetPos(pos)
		jar:Spawn()
	end

	function world:BeginHaunting(count, minDuration, maxDuration)
		WETSAND.Feature("haunting"):BeginHaunting(count, minDuration, maxDuration)
	end

	return world
end

-- wheel_of_doom: kv = { duration, hasSpiral }. Spawn clears the HUD.
function Controller:Bind(ent, kv)
	local run = {
		model = Wheel.New(kv),
		world = World(self, ent),
	}
	self.wheels[ent] = run
	self:ClearEffectStatus()
	return run.model
end

function Controller:Unbind(ent)
	self.wheels[ent] = nil
end

function Controller:Input(ent, input)
	local run = self.wheels[ent]
	if input == Wheel.INPUT_SPIN then
		run.model:Spin(run.world)
	else
		run.model:ClearAllEffects(run.world)
	end
end

-- The boss timer's question: is this wheel still spinning or naming its
-- effect?
function Controller:Busy(ent)
	return not self.wheels[ent].model:IsDoneBroadcastingEffectSound(CurTime())
end

hook.Add("Think", THINK_HOOK, function()
	for ent, run in pairs(Controller.wheels) do
		if IsValid(ent) then run.model:Think(run.world) end
	end
end)

-- player_spawn fires once the spawn is done: the conditions and attributes
-- it clears are cleared by then.
hook.Add("PlayerSpawn", THINK_HOOK, function(ply)
	timer.Simple(0, function()
		if not IsValid(ply) then return end
		ply:SetGravity(Controller.gravity)
		for ent, run in pairs(Controller.wheels) do
			if IsValid(ent) then run.model:PlayerSpawned(run.world, ply) end
		end
	end)
end)

return Controller
