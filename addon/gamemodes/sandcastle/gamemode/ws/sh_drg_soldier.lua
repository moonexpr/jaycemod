-- What every AI war soldier entity shares, whatever DrGBase base it is
-- built on (drgbase_nextbot_human for the Combine and the Resistance's
-- fighters, drgbase_nextbot for the vortigaunt): WS.DrgSoldier(ENT,
-- baseName) installs it. The controller (features/aiwar) sets NSTarget,
-- a position to go to, WSRun, whether to run there, NSLook, where to
-- face while it stands with no enemy (the threat it watches), and NSBrain,
-- the orders it asks and tells (whether to attack, which enemy, what it saw
-- and suffered). With a target, the soldier walks it whatever else it does,
-- fighting on the way; without one it is left to DrGBase.
--
-- On clients, the heal beams of medics (their "WSHealing" target).
local GOAL_TOLERANCE = 32

-- Tracing (ws_aiwar_trace): a soldier with NSTrace set prints
-- every query it asks its orders, with the answer, and every event it tells
-- them.
local function Trace(self, text)
	if self.NSTrace then print(string.format("[aiwar #%d %.2f] %s", self:EntIndex(), CurTime(), text)) end
end

local function Show(value)
	if isentity(value) then return IsValid(value) and (value:GetClass() .. " #" .. value:EntIndex()) or "NULL" end
	return tostring(value)
end

function WS.DrgSoldier(ENT, baseName)
	ENT.WSSoldier = true -- on both realms: the NPC context menu offers its trace
	if CLIENT then return end
	local Ragdoll = WS.require("foundation.npc.ragdoll")
	local Voices = WS.require("foundation.npc.voices")
	local SILENT = { pain = {}, death = {} }

	-- Its pain and death sounds, which DrGBase plays, for the model it wears
	-- now (foundation.npc.voices); none for a model without a voice.
	function ENT:NSVoice()
		local voice = Voices.For(self:GetModel()) or SILENT
		self.OnDamageSounds, self.OnDeathSounds = voice.pain, voice.death
	end

	-- DrGBase's, once it has picked the soldier's model.
	function ENT:CustomInitialize()
		self:NSVoice()
	end

	-- Walks the controller's target, if it has one, or, there, faces the
	-- enemy so it can fight (a soldier holding its ground), else watches
	-- NSLook: true when it has a target.
	function ENT:NSSteer(enemy)
		-- frozen (the match's end): it stands where it is
		if self.NSFrozen then return true end
		-- riding the cart: the controller carries it; it only turns to fight
		if self.NSSeated then
			if IsValid(enemy) then self:FaceTowards(enemy) end
			return true
		end
		local target = self.NSTarget
		if not target then return false end
		if self:GetPos():DistToSqr(target) > GOAL_TOLERANCE * GOAL_TOLERANCE then
			self.NSMoveResult = self:FollowPath(target, GOAL_TOLERANCE)
		elseif IsValid(enemy) then
			self:FaceTowards(enemy)
		elseif self.NSLook then
			self:FaceTowards(self.NSLook)
		end
		return true
	end

	-- No enemy: the target, else stand watching NSLook (DrGBase would
	-- wander off at random).
	function ENT:OnIdle()
		if not self:NSSteer() and self.NSLook then self:FaceTowards(self.NSLook) end
	end

	-- An enemy: with a target the soldier keeps to it, and DrGBase still aims
	-- and fires at the enemy in sight; without one, DrGBase's own chase,
	-- retreat and facing.
	function ENT:OnChaseEnemy(enemy) return self:NSSteer(enemy) end
	function ENT:OnAvoidEnemy(enemy) return self:NSSteer(enemy) end
	function ENT:OnIdleEnemy(enemy) return self:NSSteer(enemy) end

	-- The bridge to the war's orders (docs/aiwar-command.md §6): DrGBase's
	-- hooks become queries and events. DrGBase's own hooks that do work
	-- (spotting an attacker, reloading) are called through.
	local Engine -- foundation.npc, required on first use

	local function Brain(self)
		local brain = self.NSBrain
		if not brain then return nil end
		Engine = Engine or WS.require("foundation.npc")
		return brain
	end

	-- The answer, or nil without a brain (Engine is loaded when it is not nil).
	local function Ask(self, name, ...)
		local brain = Brain(self)
		if not brain then return nil end
		local answer = brain:Query(name, ...)
		if self.NSTrace then
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
		if self.NSTrace then
			local args = {}
			for i = 1, select("#", ...) do args[i] = Show((select(i, ...))) end
			Trace(self, string.format("tell %s(%s)", name, table.concat(args, ", ")))
		end
		brain:Event(name, ...)
	end

	local function Base() return baseclass.Get(baseName) end

	-- ShouldAttack NO skips DrGBase's attack (the humiliated, a healing
	-- medic), as does a freeze.
	function ENT:OnRangeAttack()
		if self.NSFrozen then return true end
		if Answered(Ask(self, "ShouldAttack", self:GetEnemy()), "ANSWER_NO") then return true end
	end

	function ENT:OnMeleeAttack()
		if self.NSFrozen then return true end
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

	-- ShouldHurry, else the controller's gait (WSRun), else run at an enemy.
	function ENT:ShouldRun()
		local hurry = Ask(self, "ShouldHurry")
		if Answered(hurry, "ANSWER_YES") then return true end
		if Answered(hurry, "ANSWER_NO") then return false end
		if self.NSRun ~= nil then return self.NSRun end
		return self:HasEnemy()
	end

	-- The controller's kit for the soldier's job: { weapons (classes to
	-- hold, the first it carries), avoid (classes not to hold, as a set, when
	-- it has another), model, health (its most), damage (its damage scale),
	-- runSpeed }; nil fields take the soldier's own.
	function ENT:NSKit(kit)
		self.NSOwnModel = self.NSOwnModel or self:GetModel()
		local model = kit.model or self.NSOwnModel
		if self:GetModel() ~= model then
			self:SetModel(model)
			self:NSVoice()
		end
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
		self.NSDamageScale = kit.damage
		self.RunSpeed = kit.runSpeed
	end

	-- Seated on the cart: the sitting pose, whatever DrGBase would play.
	function ENT:OnUpdateAnimation()
		if self.NSSeated then return ACT_HL2MP_SIT, 1 end
		return Base().OnUpdateAnimation(self)
	end

	function ENT:OnDealtDamage()
		return self.NSDamageScale
	end

	-- Dead: no ragdoll on the server at all (RagdollOnDeath is false, so
	-- DrGBase only removes the body). DrGBase's death callback, OnDeath, runs
	-- in its behaviour coroutine: every client near is told to ragdoll its
	-- own copy of the soldier (ws/sv_npc_ragdolls.lua), and the soldier
	-- lingers, not solid, Ragdoll.HANDOFF seconds while the message arrives,
	-- before DrGBase removes it. The method is ours: NextBot's BecomeRagdoll
	-- belongs to the engine (and DrGBase), and an ENT method of that name is
	-- never reached.
	function ENT:NSClientRagdoll(dmg)
		if not Ragdoll.LeavesBody(self:IsFlagSet(FL_DISSOLVING), dmg:IsDamageType(DMG_REMOVENORAGDOLL)) then return false end
		self:SetNotSolid(true)
		self.NSTarget = nil
		WS.SendClientRagdoll(self, dmg:GetDamageForce())
		return true
	end

	function ENT:OnDeath(dmg)
		if self:NSClientRagdoll(dmg) then self:PauseCoroutine(Ragdoll.HANDOFF) end
	end
end

if SERVER then return end

-- Heal beams: from a medic ("WSHealing", set by the controller while
-- it heals) to its patient, a band of light in its side's colour with a
-- glow where it lands.
local BEAM = Material("sprites/physbeam")
local GLOW = Material("sprites/light_glow02_add")
local BEAM_COLOR = { ws_drg_vortigaunt = Color(150, 255, 120), default = Color(120, 190, 255) }
local BEAM_LIFT = Vector(0, 0, 16)

hook.Add("PostDrawTranslucentRenderables", "ws_heal_beams", function(depth, skybox)
	if skybox then return end
	for _, medic in ipairs(ents.FindByClass("ws_drg_*")) do
		local patient = medic:GetNW2Entity("WSHealing")
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
