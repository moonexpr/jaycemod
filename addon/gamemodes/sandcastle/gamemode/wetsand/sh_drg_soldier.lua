-- What every AI war soldier entity shares, whatever DrGBase base it is
-- built on (drgbase_nextbot_human for the Combine and the Resistance's
-- fighters, drgbase_nextbot for the vortigaunt): WETSAND.DrgSoldier(ENT,
-- baseName) installs it. The controller (features/aiwar) sets WetsandTarget,
-- a position to go to, WetsandRun, whether to run there, and WetsandBrain,
-- the orders it asks and tells (whether to attack, which enemy, what it saw
-- and suffered). With a target, the soldier walks it whatever else it does,
-- fighting on the way; without one it is left to DrGBase.
--
-- On clients, the heal beams of medics (their "WetsandHealing" target).
local GOAL_TOLERANCE = 32

-- Tracing (wetsand_aiwar_trace): a soldier with WetsandTrace set prints
-- every query it asks its orders, with the answer, and every event it tells
-- them.
local function Trace(self, text)
	if self.WetsandTrace then print(string.format("[aiwar #%d %.2f] %s", self:EntIndex(), CurTime(), text)) end
end

local function Show(value)
	if isentity(value) then return IsValid(value) and (value:GetClass() .. " #" .. value:EntIndex()) or "NULL" end
	return tostring(value)
end

function WETSAND.DrgSoldier(ENT, baseName)
	if CLIENT then return end

	-- Walks the controller's target, if it has one, or, there, faces the
	-- enemy so it can fight (a soldier holding its ground): true when it has
	-- a target.
	function ENT:WetsandSteer(enemy)
		-- riding the cart: the controller carries it; it only turns to fight
		if self.WetsandSeated then
			if IsValid(enemy) then self:FaceTowards(enemy) end
			return true
		end
		local target = self.WetsandTarget
		if not target then return false end
		if self:GetPos():DistToSqr(target) > GOAL_TOLERANCE * GOAL_TOLERANCE then
			self.WetsandMoveResult = self:FollowPath(target, GOAL_TOLERANCE)
		elseif IsValid(enemy) then
			self:FaceTowards(enemy)
		end
		return true
	end

	-- No enemy: the target, else stand (DrGBase would wander off at random).
	function ENT:OnIdle()
		self:WetsandSteer()
	end

	-- An enemy: with a target the soldier keeps to it, and DrGBase still aims
	-- and fires at the enemy in sight; without one, DrGBase's own chase,
	-- retreat and facing.
	function ENT:OnChaseEnemy(enemy) return self:WetsandSteer(enemy) end
	function ENT:OnAvoidEnemy(enemy) return self:WetsandSteer(enemy) end
	function ENT:OnIdleEnemy(enemy) return self:WetsandSteer(enemy) end

	-- The bridge to the war's orders (docs/aiwar-command.md §6): DrGBase's
	-- hooks become queries and events. DrGBase's own hooks that do work
	-- (spotting an attacker, reloading) are called through.
	local Engine -- foundation.npc, required on first use

	local function Brain(self)
		local brain = self.WetsandBrain
		if not brain then return nil end
		Engine = Engine or WETSAND.require("foundation.npc")
		return brain
	end

	-- The answer, or nil without a brain (Engine is loaded when it is not nil).
	local function Ask(self, name, ...)
		local brain = Brain(self)
		if not brain then return nil end
		local answer = brain:Query(name, ...)
		if self.WetsandTrace then
			local args = {}
			for i = 1, select("#", ...) do args[i] = Show((select(i, ...))) end
			local named = { [Engine.ANSWER_NO] = "NO", [Engine.ANSWER_YES] = "YES", [Engine.ANSWER_UNDEFINED] = "undefined" }
			Trace(self, string.format("ask %s(%s) -> %s", name, table.concat(args, ", "), named[answer] or Show(answer)))
		end
		return answer
	end

	local function Answered(answer, which)
		return answer ~= nil and answer == Engine[which]
	end

	local function Tell(self, name, ...)
		local brain = Brain(self)
		if not brain then return end
		if self.WetsandTrace then
			local args = {}
			for i = 1, select("#", ...) do args[i] = Show((select(i, ...))) end
			Trace(self, string.format("tell %s(%s)", name, table.concat(args, ", ")))
		end
		brain:Event(name, ...)
	end

	local function Base() return baseclass.Get(baseName) end

	-- ShouldAttack NO skips DrGBase's attack (the humiliated, a healing medic).
	function ENT:OnRangeAttack()
		if Answered(Ask(self, "ShouldAttack", self:GetEnemy()), "ANSWER_NO") then return true end
	end

	function ENT:OnMeleeAttack()
		if Answered(Ask(self, "ShouldAttack", self:GetEnemy()), "ANSWER_NO") then return true end
	end

	-- SelectMoreDangerousThreat: true when a is the one to fight; nil leaves
	-- DrGBase's order (priority, then range).
	function ENT:OnFetchEnemy(a, b)
		local pick = Ask(self, "SelectMoreDangerousThreat", a, b)
		if pick == a then return true end
		if pick == b then return false end
		return nil
	end

	function ENT:OnTakeDamage(dmg, hitgroup)
		local result = Base().OnTakeDamage(self, dmg, hitgroup)
		Tell(self, "OnInjured", dmg:GetAttacker(), dmg:GetDamage())
		return result
	end

	function ENT:OnSpotted(ent) Tell(self, "OnSight", ent) end
	function ENT:OnLost(ent) Tell(self, "OnLostSight", ent) end
	function ENT:OnNewEnemy(ent) Tell(self, "OnContact", ent) end

	function ENT:OnLastEnemy(ent)
		Base().OnLastEnemy(self, ent)
		Tell(self, "OnContactLost", ent)
	end

	function ENT:OnNavAreaChanged(old, new) Tell(self, "OnNavAreaChanged", old, new) end

	-- ShouldHurry, else the controller's gait (WetsandRun), else run at an enemy.
	function ENT:ShouldRun()
		local hurry = Ask(self, "ShouldHurry")
		if Answered(hurry, "ANSWER_YES") then return true end
		if Answered(hurry, "ANSWER_NO") then return false end
		if self.WetsandRun ~= nil then return self.WetsandRun end
		return self:HasEnemy()
	end

	-- The controller's kit for the soldier's job: { weapons (classes to
	-- hold, the first it carries), avoid (classes not to hold, as a set, when
	-- it has another), model, health (its most), damage (its damage scale),
	-- runSpeed }; nil fields take the soldier's own.
	function ENT:WetsandKit(kit)
		self.WetsandOwnModel = self.WetsandOwnModel or self:GetModel()
		local model = kit.model or self.WetsandOwnModel
		if self:GetModel() ~= model then self:SetModel(model) end
		local held
		for _, class in ipairs(kit.weapons or {}) do
			if self:HasWeapon(class) then
				held = self:SelectWeapon(class)
				break
			end
		end
		local active = self:GetActiveWeapon()
		if not held and kit.avoid and IsValid(active) and kit.avoid[active:GetClass()] then
			local others = {}
			for class, weapon in pairs(self:GetWeapons()) do
				if not kit.avoid[class] and IsValid(weapon) then others[#others + 1] = class end
			end
			if #others > 0 then self:SelectWeapon(others[math.random(#others)]) end
		end
		local most = kit.health or self.SpawnHealth
		if self:GetMaxHealth() ~= most then
			self:SetHealth(math.max(1, math.floor(self:Health() * most / math.max(self:GetMaxHealth(), 1))))
			self:SetMaxHealth(most)
		end
		self.WetsandDamageScale = kit.damage
		self.RunSpeed = kit.runSpeed
	end

	-- Seated on the cart: the sitting pose, whatever DrGBase would play.
	function ENT:OnUpdateAnimation()
		if self.WetsandSeated then return ACT_HL2MP_SIT, 1 end
		return Base().OnUpdateAnimation(self)
	end

	function ENT:OnDealtDamage()
		return self.WetsandDamageScale
	end

	-- Dead: while wetsand_aiwar_client_ragdolls is on, no ragdoll on the
	-- server at all. Every client near is told to make its own from the
	-- soldier's last pose (wetsand/sh_aiwar.lua), and the soldier is removed
	-- a moment later, once they have. Off, DrGBase's serverside one.
	local RAGDOLL_HANDOFF = 0.3

	function ENT:BecomeRagdoll(dmg)
		local clientside = GetConVar("wetsand_aiwar_client_ragdolls")
		if clientside and not clientside:GetBool() then return FindMetaTable("NextBot").BecomeRagdoll(self, dmg) end
		if self.WetsandRagdolled then return NULL end
		self.WetsandRagdolled = true
		net.Start("wetsand_soldier_ragdoll")
		net.WriteEntity(self)
		net.WriteVector(dmg and dmg:GetDamageForce() or vector_origin)
		net.SendPVS(self:GetPos())
		self:SetNotSolid(true)
		self.WetsandTarget = nil
		SafeRemoveEntityDelayed(self, RAGDOLL_HANDOFF)
		return NULL
	end
end

if SERVER then return end

-- Heal beams: from a medic ("WetsandHealing", set by the controller while
-- it heals) to its patient, a band of light in its side's colour with a
-- glow where it lands.
local BEAM = Material("sprites/physbeam")
local GLOW = Material("sprites/light_glow02_add")
local BEAM_COLOR = { wetsand_drg_vortigaunt = Color(150, 255, 120), default = Color(120, 190, 255) }
local BEAM_LIFT = Vector(0, 0, 16)

hook.Add("PostDrawTranslucentRenderables", "wetsand_heal_beams", function(depth, skybox)
	if skybox then return end
	for _, medic in ipairs(ents.FindByClass("wetsand_drg_*")) do
		local patient = medic:GetNW2Entity("WetsandHealing")
		if IsValid(patient) then
			local from = medic:WorldSpaceCenter() + BEAM_LIFT
			local to = patient:WorldSpaceCenter()
			local color = BEAM_COLOR[medic:GetClass()] or BEAM_COLOR.default
			local pulse = 10 + math.sin(CurTime() * 8) * 3
			render.SetMaterial(BEAM)
			render.DrawBeam(from, to, pulse, CurTime() * 2, CurTime() * 2 + 1, color)
			render.SetMaterial(GLOW)
			render.DrawSprite(to, 40 + pulse * 2, 40 + pulse * 2, color)
		end
	end
end)
