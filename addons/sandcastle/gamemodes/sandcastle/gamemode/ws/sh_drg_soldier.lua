-- What every AI war soldier entity shares, whatever DrGBase base it is
-- built on (drgbase_nextbot_human for the Combine and the Resistance's
-- fighters, drgbase_nextbot for the vortigaunt): WS.DrgSoldier(ENT,
-- baseName) installs it. The controller (features/aiwar) sets NSTarget,
-- a position to go to, NSRun, whether to run there, NSLook, where to
-- face while it stands with no enemy (the threat it watches), and NSBrain,
-- the orders it asks and tells (whether to attack, which enemy, what it saw
-- and suffered). With a target, the soldier walks it whatever else it does,
-- fighting on the way; without one it is left to DrGBase.
--
-- On clients, the heal beams of medics (their "WSHealing" target) are
-- ws/cl_medic_effects.lua's.
local GOAL_TOLERANCE = 32
-- How near each of its path's points the soldier comes before the next
-- (the path's own goal tolerance): a point round a wall's end, passed at
-- GOAL_TOLERANCE while still short of the end, sends it into the wall.
local PATH_TOLERANCE = 12
-- Moved farther than this between two steps (put back at spawn, revived,
-- thrown clear of a cart: any SetPos), the soldier plans its path afresh:
-- the old one led from where it was.
local TELEPORT = 128
-- m_lifeState of a living entity (shareddefs.h); GMod names none.
local LIFE_ALIVE = 0
-- A ledge jump (CustomClimbing): how far in from its hull a soldier checks
-- the way up and the landing, so the wall it stands against is not in the
-- way; how long after a jump it found no way for it does not try another.
local LEAP_INSET, LEAP_RETRY = 2, 1
-- A vault (NSVault) over what it cannot stand on, a railing: how far ahead
-- it looks for the obstacle; past its face, how far it looks for the floor
-- beyond, in steps of how much; and how far onto that floor it lands.
local VAULT_REACH, VAULT_SCAN, VAULT_SCAN_STEP, VAULT_LAND_IN = 48, 64, 8, 8
-- An obstacle's top is looked for along this far past where the hull met it,
-- this often: a rail a few units thick stands between lines farther apart.
local TOP_SCAN, TOP_SCAN_STEP = 16, 2
-- A plain hop when no vault fits: this fast the way it heads, up as high as
-- it jumps.
local HOP_SPEED = 200
-- The sound level of its steps and landings (PlayStepSound's SNDLVL_NORM),
-- as the soldiers in earshot hear them (NSNotice), and of its grunts and cries.
local STEP_LEVEL, VOICE_LEVEL = 75, 75
-- How its steps and landings play to players: farther than a player's (the
-- level) and as loud as theirs (Noise.Played), the step sound of the surface
-- under it, left foot then right, as a player's are (so TF2's own, through
-- ws/sh_soundscripts.lua). STEP_REACH: how far down it looks for the surface.
local STEP_PLAY_LEVEL, STEP_REACH = 85, 64

-- volume: as it plays (Noise.Played); gear: what its gear rattles with the
-- step (Voices.Gear: a Combine soldier's, quietly), or nil.
local function PlayStep(self, volume, gear)
	local pos = self:GetPos()
	local tr = util.TraceLine({ start = pos, endpos = pos - Vector(0, 0, STEP_REACH), filter = self, mask = MASK_PLAYERSOLID })
	local surface = util.GetSurfaceData(tr.SurfaceProps)
	self.NSLeftFoot = not self.NSLeftFoot
	local sound = self.NSLeftFoot and surface.stepLeftSound or surface.stepRightSound
	self:EmitSound(sound, STEP_PLAY_LEVEL, 100, volume, CHAN_BODY)
	if gear then self:EmitSound(gear.sound, gear.level, gear.pitch, gear.volume, CHAN_AUTO) end
end

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
	local HL2Path = WS.require("games.ns.path.hl2")
	local Leap = WS.require("games.ns.leap")
	local Noise = WS.require("games.ns.noise")
	local Rappel = WS.require("games.ns.rappel")
	local Arms = WS.require("features.aiwar.arms")
	local SILENT = { grunt = {}, pain = {}, death = {}, fall = {} }

	local function Base() return baseclass.Get(baseName) end

	-- One of a voice's lines, if it has any.
	local function Say(self, lines)
		if #lines > 0 then self:EmitSound(lines[math.random(#lines)], VOICE_LEVEL) end
	end

	-- It climbs a ledge as high as its route may (DrGBase's path to each
	-- target then takes it) by jumping it (CustomClimbing).
	ENT.ClimbLedges = true
	ENT.ClimbLedgesMaxHeight = HL2Path.SOLDIER_LIMITS.jumpHeight
	-- It goes down drops as deep as its routes may (DrGBase's paths then take
	-- them), rappelling one deeper than a safe fall (NSRappel).
	ENT.DeathDropHeight = HL2Path.SOLDIER_LIMITS.deathDropHeight

	-- Its voice for the model it wears now (foundation.npc.voices; none for a
	-- model without one): it plays its hits' grunts and cries (NSFeedback) and
	-- its death (OnDeath: WS.PlayDeath, loud and confirmed) itself, not
	-- DrGBase.
	function ENT:NSVoice()
		local voice = Voices.For(self:GetModel()) or SILENT
		self.NSVoiceLines = voice
		self.OnDamageSounds, self.OnDeathSounds = {}, {}
	end

	-- A hit it lives through: a grunt, or for a heavy one a cry of pain
	-- (Voices.Feedback), not again for Voices.FEEDBACK_COOLDOWN.
	function ENT:NSFeedback(damage)
		local now = CurTime()
		if damage <= 0 or self:Health() - damage <= 0 or now < (self.NSNextFeedback or 0) then return end
		self.NSNextFeedback = now + Voices.FEEDBACK_COOLDOWN
		Say(self, self.NSVoiceLines[Voices.Feedback(damage, self:GetMaxHealth())])
	end

	-- How often a soldier with an enemy checks it holds the weapon for the
	-- enemy's distance (NSArm).
	local ARM_INTERVAL = 0.25

	-- Each think: the weapon for its enemy's distance, every ARM_INTERVAL;
	-- its footsteps, timed by its speed as a player's are (Noise.Step), and
	-- in the air, how fast it is falling (for its landing).
	function ENT:CustomThink()
		if self.NSDormant then return end
		local now = CurTime()
		if now >= (self.NSNextArm or 0) and self:HasEnemy() then
			self.NSNextArm = now + ARM_INTERVAL
			self:NSArm(self:GetEnemy())
		end
		local velocity = self.loco:GetVelocity()
		if not self:IsOnGround() then
			self.NSFallSpeed = math.max(self.NSFallSpeed or 0, -velocity.z)
			self:NSRappel(velocity)
			return
		end
		self.NSRappelling = nil
		local step = Noise.Step(velocity:Length2D(), self.IsCrouching ~= nil and self:IsCrouching())
		if step and now >= (self.NSNextStep or 0) then
			PlayStep(self, Noise.Played(step.volume), self:NSGear(step.running))
			self.NSNextStep = now + step.interval
		end
	end

	-- Going down a drop it would land from faster than a safe fall, it comes
	-- down no faster than a rappel (games.ns.rappel), to the floor.
	local RAPPEL_LOOK = 4096
	function ENT:NSRappel(velocity)
		if velocity.z >= 0 then return end
		local pos = self:GetPos()
		local floor = util.TraceLine({ start = pos, endpos = pos - Vector(0, 0, RAPPEL_LOOK), mask = self:GetSolidMask(), filter = self })
		local height = floor.Hit and pos.z - floor.HitPos.z or RAPPEL_LOOK
		local speed, rappelling = Rappel.Descent(-velocity.z, height, GetConVar("sv_gravity"):GetFloat(), self.NSRappelling)
		self.NSRappelling = rappelling or nil
		if speed < -velocity.z then self.loco:SetVelocity(Vector(velocity.x, velocity.y, -speed)) end
	end

	-- What its gear rattles with its next step (the foot after the last).
	function ENT:NSGear(running)
		return Voices.Gear(self.NSVoiceLines, self.NSLeftFoot and "right" or "left", running, math.random)
	end

	-- Holds its loadout's weapon for the enemy's distance (Arms.Choose).
	function ENT:NSArm(enemy)
		local loadout = self.NSLoadout
		if not loadout or not IsValid(enemy) then return end
		local class = Arms.Choose(loadout, self:GetPos():Distance(enemy:GetPos()))
		local active = self:GetActiveWeapon()
		if not (IsValid(active) and active:GetClass() == class) then self:SelectWeapon(class) end
	end

	-- A weapon in hand: its ranges are the arms' (a gun fires at any enemy in
	-- sight), in place of DrGBase's for the hold type; a weapon the arms do
	-- not know keeps DrGBase's.
	function ENT:OnWeaponChange(old, new)
		local ranges = IsValid(new) and Arms.Ranges(new:GetClass())
		if not ranges then return end
		self.RangeAttackRange = ranges.attack
		self.MeleeAttackRange = ranges.melee
		self.ReachEnemyRange = ranges.chase
		self.AvoidEnemyRange = ranges.avoid
		return true
	end

	-- Its steps are timed (CustomThink), not the walk animation's.
	function ENT:OnAnimEvent(event, ...)
		if event == "PlayerStep" then return end
		return Base().OnAnimEvent(self, event, ...)
	end

	-- Landing: DrGBase's own handling (its ground state, fall damage), as its
	-- mixin wraps the base's hook, then the impact: a step as loud as the fall
	-- was fast (Noise.Landing; a jump onto a ledge, as a jump's), a brief
	-- landing animation, a grunt for a hard landing or a cry for a hurtful
	-- one, and the enemies in earshot notice it (NSNotice).
	function ENT:OnLandOnGround(ground)
		self:_HandleLandOnGround(ground)
		local fall = self.NSFallSpeed or 0
		local volume = self.NSLeapt and Noise.JUMP_LANDING_VOLUME or Noise.Landing(fall)
		self.NSFallSpeed, self.NSLeapt = 0, nil
		if volume <= 0 then return end
		-- a landing jolts its gear as a run does
		PlayStep(self, Noise.Played(volume), self:NSGear(true))
		local landing = self:SelectWeightedSequence(ACT_LAND)
		if landing and landing > 0 then self:AddGestureSequence(landing, true) end
		if fall > Noise.MAX_SAFE_FALL_SPEED then
			Say(self, self.NSVoiceLines.fall)
		elseif Noise.HardLanding(fall) then
			Say(self, self.NSVoiceLines.grunt)
		end
		self:NSNotice(STEP_LEVEL, volume)
	end

	-- A noise of its body that the NextBots in earshot hear (Noise.Hears, as
	-- DrGBase hears a player's: DrGBase hears no NextBot's), noticing it as
	-- DrGBase's OnSound does.
	function ENT:NSNotice(level, volume)
		local pos = self:GetPos()
		local sound = { Entity = self, Pos = pos, SoundLevel = level, Volume = volume }
		local reach = Noise.HearingRange(level, volume)
		for _, bot in ipairs(DrGBase.GetNextbots()) do
			if bot ~= self and not bot:IsAIDisabled() and not bot:IsDeaf() then
				local coefficient = bot:GetHearingCoefficient()
				local distance = bot:GetRangeTo(pos)
				-- the sight test only for one near enough to hear it seen
				if distance <= reach * coefficient and Noise.Hears(level, volume, distance, bot:VisibleVec(pos), coefficient) then
					bot:Timer(0, bot.OnSound, self, sound)
				end
			end
		end
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
		-- the orders' hop, planned when it was stuck (NSHop)
		if self.NSHopPlan then
			local plan = self.NSHopPlan
			self.NSHopPlan = nil
			if plan.dir then
				self:NSHopPlain(plan.dir)
				self.NSMoveResult = "hopped"
			else
				self:NSVaultRun(plan)
				self.NSMoveResult = "vaulted"
			end
			return true
		end
		local target = self.NSTarget
		local here = self:GetPos()
		if self.NSLastPos and here:DistToSqr(self.NSLastPos) > TELEPORT * TELEPORT then self:NSRepath() end
		self.NSLastPos = here
		if not target then return false end
		if here:DistToSqr(target) > GOAL_TOLERANCE * GOAL_TOLERANCE then
			local result = self:FollowPath(target, PATH_TOLERANCE)
			if result == "obstacle" and self:NSVault() then result = "vaulted" end
			self.NSMoveResult = result
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
	local Engine -- games.npc.nextbot, required on first use

	local function Brain(self)
		local brain = self.NSBrain
		if not brain then return nil end
		Engine = Engine or WS.require("games.npc.nextbot")
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

	-- ShouldAttack NO skips DrGBase's attack (the humiliated, a healing
	-- medic), as do a freeze and the reaction time to a new enemy
	-- (NSReactAt, tf_bot_difficulty's).
	function ENT:OnRangeAttack()
		if self.NSFrozen or CurTime() < (self.NSReactAt or 0) then return true end
		if Answered(Ask(self, "ShouldAttack", self:GetEnemy()), "ANSWER_NO") then return true end
	end

	-- DrGBase's human AI holds a melee weapon but never strikes with it: the
	-- soldier strikes the enemy in reach for the weapon's damage, at its
	-- pace (features.aiwar.arms), playing the melee swing.
	function ENT:OnMeleeAttack(enemy, weapon)
		if self.NSFrozen then return true end
		if Answered(Ask(self, "ShouldAttack", self:GetEnemy()), "ANSWER_NO") then return true end
		local arm = IsValid(weapon) and Arms.WEAPONS[weapon:GetClass()]
		local now = CurTime()
		if not (arm and arm.melee) or now < (self.NSNextStrike or 0) or not IsValid(enemy) then return true end
		self.NSNextStrike = now + arm.interval
		self:FaceTowards(enemy)
		self:AddGesture(ACT_HL2MP_GESTURE_RANGE_ATTACK_MELEE)
		local dmg = DamageInfo()
		dmg:SetDamage(arm.damage)
		dmg:SetDamageType(DMG_CLUB)
		dmg:SetAttacker(self)
		dmg:SetInflictor(weapon)
		dmg:SetDamageForce(self:GetForward() * arm.damage * 100)
		dmg:SetDamagePosition(enemy:WorldSpaceCenter())
		enemy:TakeDamageInfo(dmg)
		return true
	end

	-- SelectMoreDangerousThreat: true when a is the one to fight; nil leaves
	-- DrGBase's order (priority, then range).
	function ENT:OnFetchEnemy(a, b)
		local pick = Ask(self, "SelectMoreDangerousThreat", a, b)
		if pick == a then return true end
		if pick == b then return false end
		return nil
	end

	-- a NextBot has no ScaleNPCDamage: its hit's group, for a headshot's
	-- crit (ws/sv_hits.lua)
	function ENT:OnTraceAttack(dmg, dir, tr)
		WS.TraceHit(self, tr.HitGroup)
		return Base().OnTraceAttack(self, dmg, dir, tr)
	end

	function ENT:OnTakeDamage(dmg, hitgroup)
		local result = Base().OnTakeDamage(self, dmg, hitgroup)
		Tell(self, "OnInjured", dmg:GetAttacker(), dmg:GetDamage())
		self:NSFeedback(dmg:GetDamage())
		return result
	end

	function ENT:OnSpotted(ent) Tell(self, "OnSight", ent) end
	function ENT:OnLost(ent) Tell(self, "OnLostSight", ent) end
	-- a new enemy: its orders hear of it, and the AI war may have it call it
	-- out (WSSoldierContact: features/aiwar/sv_speech.lua)
	function ENT:OnNewEnemy(ent)
		-- the weapon for it at once: it fires as it calls them out
		self:NSArm(ent)
		Tell(self, "OnContact", ent)
		hook.Run("WSSoldierContact", self, ent)
	end

	function ENT:OnLastEnemy(ent)
		Base().OnLastEnemy(self, ent)
		Tell(self, "OnContactLost", ent)
		hook.Run("WSSoldierContactLost", self, ent)
	end

	-- In an area a TF2 player crouches through, the soldier crouches (the
	-- vortigaunt's base has no crouch): its hull passes under the ceiling
	-- either way, but not its model.
	function ENT:OnNavAreaChanged(old, new)
		if self.SetCrouching then self:SetCrouching(IsValid(new) and HL2Path.MustCrouch(new:GetAttributes())) end
		Tell(self, "OnNavAreaChanged", old, new)
	end

	-- A ledge (not a ladder, which DrGBase climbs) it jumps: CustomClimbing;
	-- not again for LEAP_RETRY after a jump with no way up.
	function ENT:OnStartClimbing(ledge, height, down)
		if isvector(ledge) and not down then
			if CurTime() < (self.NSLeapRetry or 0) then return false end
			return true
		end
		return Base().OnStartClimbing(self, ledge, height, down)
	end

	-- Jumps onto the ledge along games.ns.leap's arc, set a step each
	-- tick of its behaviour, its own momentum stopped, as DrGBase's own climb
	-- moves it: if the way straight up to the arc's top and across to its
	-- landing is clear (the arc stays inside that, and clears the lip), else
	-- it stays.
	function ENT:CustomClimbing(ledge)
		local from, began = self:GetPos(), CurTime()
		local mins, maxs = self:GetCollisionBounds()
		-- from step height up, as DrGBase's ledge trace: a sloped floor is no wall
		local hull = {
			mins = Vector(mins.x + LEAP_INSET, mins.y + LEAP_INSET, self.loco:GetStepHeight()),
			maxs = maxs - Vector(LEAP_INSET, LEAP_INSET, LEAP_INSET),
		}
		local function Clear(a, b)
			hull.start = a
			return not self:TraceHull(b - a, hull).Hit
		end
		-- and its body fits where it lands, from step height up as the rest (a
		-- slope under it is no wall): a ledge that is a thin plate's edge (a
		-- stage over open space) would leave it set inside the plate
		local function Fits(p) return Clear(p, p) end
		local land = Leap.Arc(from, ledge, 1)
		land = Vector(land.x, land.y, land.z)
		local top = Vector(from.x, from.y, land.z)
		if not (Clear(from, top) and Clear(top, land) and Fits(land)) then
			self.NSLeapRetry = CurTime() + LEAP_RETRY
			return
		end
		self:FaceTowards(ledge)
		self:SetNW2Bool("DrGBaseJumping", true)
		while true do
			self.loco:SetVelocity(vector_origin)
			local t = (CurTime() - began) / Leap.DURATION
			local p = Leap.Arc(from, ledge, t)
			self:SetPos(Vector(p.x, p.y, p.z))
			if t >= 1 then break end
			self:YieldCoroutine(false)
		end
		self.NSLeapt = true
		self:SetNW2Bool("DrGBaseJumping", false)
	end

	-- A vault over what stands toward dir (flat, of unit length) along
	-- games.ns.leap's arc: when the obstacle's top is no higher than it
	-- climbs (ClimbLedgesMaxHeight), the floor beyond is on the nav mesh no
	-- farther down than it falls (the death drop), and its hull clears the
	-- way up, over and down (Leap.VaultFits). The plan, { from, top, land },
	-- or nil and why there is no way over.
	function ENT:NSVaultPlan(dir)
		local from = self:GetPos()
		-- what it collides with here: a players' map's player clips too (the
		-- rail along a walkway a bullet passes), which MASK_NPCSOLID misses
		local mask = WS.ClipMasks().solid
		local mins, maxs = self:GetCollisionBounds()
		local step = self.loco:GetStepHeight()
		local hull = {
			mins = Vector(mins.x + LEAP_INSET, mins.y + LEAP_INSET, step),
			maxs = maxs - Vector(LEAP_INSET, LEAP_INSET, LEAP_INSET),
		}
		-- nil when the hull passes from a to b, else what it hit
		local function Sweep(a, b)
			return util.TraceHull({ start = a, endpos = b, mins = hull.mins, maxs = hull.maxs, mask = mask, filter = self })
		end
		local function Hits(a, b)
			local tr = Sweep(a, b)
			if not tr.Hit then return nil end
			return tr.HitWorld and "the map" or tostring(tr.Entity)
		end
		local blocked = Sweep(from, from + dir * VAULT_REACH)
		if not blocked.Hit then return nil, "nothing in the way" end
		-- the obstacle's face, and its top: the highest point of it above a
		-- step and within reach, over TOP_SCAN past the face, each line down
		-- from under whatever hangs above (a ceiling, a pipe)
		local face = from + dir * (blocked.Fraction * VAULT_REACH + maxs.x)
		local reach = self.ClimbLedgesMaxHeight
		local top
		for d = -LEAP_INSET, TOP_SCAN, TOP_SCAN_STEP do
			local p = face + dir * d
			local floorStep, ceiling = p + Vector(0, 0, step), p + Vector(0, 0, reach + 1)
			-- over the obstacle the line up starts inside it: down from reach
			local up = util.TraceLine({ start = floorStep, endpos = ceiling, mask = mask, filter = self })
			local start = (up.Hit and not up.StartSolid) and up.HitPos - Vector(0, 0, 1) or ceiling
			local down = util.TraceLine({ start = start, endpos = floorStep, mask = mask, filter = self })
			if down.Hit and not down.StartSolid and (not top or down.HitPos.z > top.z) then top = down.HitPos end
		end
		-- none (a rail whose bars no line found, a lip it cannot stand on):
		-- it hops anyway, as high as it jumps, rather than ram it, the floor
		-- beyond and the way over checked as for a vault
		if not top then top = face + Vector(0, 0, HL2Path.SOLDIER_LIMITS.jumpHeight) end
		-- the floor beyond: the first lower than the top, landed on a hull's width in
		local drop = self.loco:GetDeathDropHeight()
		local land
		for d = VAULT_SCAN_STEP, VAULT_SCAN, VAULT_SCAN_STEP do
			local p = face + dir * d
			local floor = util.TraceLine({ start = Vector(p.x, p.y, top.z + Leap.CLEARANCE), endpos = Vector(p.x, p.y, from.z - drop - 1), mask = mask, filter = self })
			if floor.Hit and not floor.StartSolid and floor.HitPos.z < top.z - 1 then
				local q = p + dir * (maxs.x + VAULT_LAND_IN)
				local under = util.TraceLine({ start = Vector(q.x, q.y, top.z + Leap.CLEARANCE), endpos = Vector(q.x, q.y, from.z - drop - 1), mask = mask, filter = self })
				if under.Hit and not under.StartSolid then land = under.HitPos end
				break
			end
		end
		if not land then return nil, "no floor beyond" end
		if not Leap.VaultFits({ from = from, top = top, land = land, maxHeight = reach, maxDrop = drop }) then return nil, "too high or too far down" end
		if not IsValid(navmesh.GetNearestNavArea(land, false, VAULT_SCAN, true, true)) then return nil, "beyond is off the nav mesh" end
		local apex = Vector(from.x, from.y, top.z + Leap.CLEARANCE)
		local over = Leap.Vault(from, top, land, Leap.VAULT_CROSS)
		over = Vector(over.x, over.y, over.z)
		local up, across, down = Hits(from, apex), Hits(apex, over), Hits(over, land)
		if up then return nil, string.format("%s in the way up (%d above)", up, top.z + Leap.CLEARANCE - from.z) end
		if across then return nil, string.format("%s in the way across", across) end
		if down then return nil, string.format("%s in the way down (%d below)", down, from.z - land.z) end
		return { from = from, top = top, land = land }
	end

	-- A vault planned (NSVaultPlan), moved each tick of its behaviour as
	-- CustomClimbing moves it; its path is planned again from where it lands.
	function ENT:NSVaultRun(plan)
		local from, top, land = plan.from, plan.top, plan.land
		self:FaceTowards(land)
		self:SetNW2Bool("DrGBaseJumping", true)
		local began = CurTime()
		while true do
			self.loco:SetVelocity(vector_origin)
			local t = (CurTime() - began) / Leap.VAULT_DURATION
			local p = Leap.Vault(from, top, land, t)
			self:SetPos(Vector(p.x, p.y, p.z))
			if t >= 1 then break end
			self:YieldCoroutine(false)
		end
		self.NSLeapt = true
		self:SetNW2Bool("DrGBaseJumping", false)
		local path = self:GetPath()
		if IsValid(path) then path:Invalidate() end
	end

	-- What it stands on, for Lua: DrGBase follows the soldier's path only on
	-- the world (FollowPath), and off it walks straight at the target into
	-- whatever stands between; a soldier on a control point's base, a prop
	-- or another soldier stands as firm, so anything that is not moving
	-- counts as the world (a moving cart or lift is itself).
	local EntityGround = FindMetaTable("Entity").GetGroundEntity
	local STILL = 1
	function ENT:GetGroundEntity()
		local ground = EntityGround(self)
		if IsValid(ground) and ground:GetVelocity():LengthSqr() < STILL * STILL then return game.GetWorld() end
		return ground
	end

	-- Its path planned afresh from where it stands, on FollowPath's next step
	-- (DrGBase computes again only as the target moves): pushed off it, the
	-- soldier would run at its next point through whatever stands between.
	function ENT:NSRepath()
		local path = self:GetPath()
		if IsValid(path) then path:Invalidate() end
	end

	-- DrGBase's cost of each link its path may take (GetPathGenerator, every
	-- link but a ladder's): none it cannot cross (WS.NavLinkCrossable: a
	-- players' map's clip along a rail, which the nav mesh links a drop past,
	-- so it would ram the rail for good), nor into an area closed to it
	-- (NSAreaClosed, which its controller gives it: a door shut to its team).
	function ENT:OnComputePath(from, to)
		if not WS.NavLinkCrossable(from, to) then return -1 end
		if self.NSAreaClosed and self.NSAreaClosed(to) then return -1 end
		return 0
	end

	-- Its path held up by an obstacle it cannot stand on (a railing, where
	-- its route drops to the floor beyond, as a player jumps it), it vaults
	-- it toward its path's next goal (NSVaultPlan). Not again for LEAP_RETRY
	-- after finding no way over. Whether it vaulted.
	function ENT:NSVault()
		if CurTime() < (self.NSLeapRetry or 0) then return false end
		self.NSLeapRetry = CurTime() + LEAP_RETRY
		local path = self:GetPath()
		if not IsValid(path) then return false end
		local dir = path:GetCurrentGoal().pos - self:GetPos()
		dir.z = 0
		if dir:Length2DSqr() < 1 then return false end
		local plan = self:NSVaultPlan(dir:GetNormalized())
		if not plan then return false end
		self.NSLeapRetry = nil
		self:NSVaultRun(plan)
		return true
	end

	-- The orders' hop when stuck (features.aiwar.orders' Unstick, through
	-- the soldier port's Hop): toward p, a vault if one fits, else a plain hop
	-- (a soldier hopping beats one ramming a wall), run at its next step
	-- (NSSteer). NSHopWhy says why no vault fitted, for the AI war's report.
	-- Whether it hops: always, but at p itself.
	function ENT:NSHop(p)
		local dir = p - self:GetPos()
		dir.z = 0
		if dir:Length2DSqr() < 1 then return false end
		dir:Normalize()
		local vault, why = self:NSVaultPlan(dir)
		self.NSHopPlan = vault or { dir = dir }
		self.NSHopWhy = why
		return true
	end

	-- A plain hop the way dir points: up as high as it jumps, HOP_SPEED across.
	function ENT:NSHopPlain(dir)
		local up = math.sqrt(2 * self.loco:GetGravity() * HL2Path.SOLDIER_LIMITS.jumpHeight)
		self.loco:Jump()
		self.loco:SetVelocity(dir * HOP_SPEED + Vector(0, 0, up))
	end

	-- ShouldHurry, else the controller's gait (NSRun), else run at an enemy.
	function ENT:ShouldRun()
		local hurry = Ask(self, "ShouldHurry")
		if Answered(hurry, "ANSWER_YES") then return true end
		if Answered(hurry, "ANSWER_NO") then return false end
		if self.NSRun ~= nil then return self.NSRun end
		return self:HasEnemy()
	end

	-- The controller's kit for the soldier's job: { primary (classes, one
	-- drawn), secondary, melee (features.aiwar.arms' Loadout: it carries
	-- these three and nothing else, the primary in hand; a kit without them,
	-- the vortigaunt's, leaves its arms alone), model, health (its most),
	-- damage (its damage scale), runSpeed }; nil fields take the soldier's own.
	function ENT:NSKit(kit)
		self.NSOwnModel = self.NSOwnModel or self:GetModel()
		local model = kit.model or self.NSOwnModel
		if self:GetModel() ~= model then
			self:SetModel(model)
			self:NSVoice()
		end
		if kit.primary then
			local loadout = Arms.Loadout(kit, math.random)
			local carried = {}
			for _, class in ipairs(Arms.Classes(loadout)) do
				carried[class] = true
				self:GiveWeapon(class)
			end
			for class in pairs(self:GetWeapons()) do
				if not carried[class] then self:RemoveWeapon(class) end
			end
			self.NSLoadout = loadout
			self:SelectWeapon(loadout.primary)
		end
		local most = kit.health or self.SpawnHealth
		if self:GetMaxHealth() ~= most then
			self:SetHealth(math.max(1, math.floor(self:Health() * most / math.max(self:GetMaxHealth(), 1))))
			self:SetMaxHealth(most)
		end
		self.NSDamageScale = kit.damage
		self.RunSpeed = kit.runSpeed
	end

	-- A battle stance (the AI war's Pose, in setup): crouched ready with its
	-- weapon, in the player model's crouch idle for the weapon's hold type,
	-- checking it (the hold type's reload gesture) as it settles.
	local STANCE_CROUCHED = "crouched"
	local STANCE_HOLD_DEFAULT = "ar2"

	local function HoldType(self)
		local weapon = self:GetActiveWeapon()
		return IsValid(weapon) and weapon:GetHoldType() or STANCE_HOLD_DEFAULT
	end

	-- The acts' names for hold types named otherwise (weapon_smg1's "smg").
	local HOLD_ACT_NAMES = { smg = "SMG1" }

	-- The act named prefix .. HOLD (ACT_HL2MP_IDLE_CROUCH_AR2), or the AR2's
	-- for a hold type the player model has none for.
	local function HoldAct(prefix, hold)
		return _G[prefix .. (HOLD_ACT_NAMES[hold] or hold:upper())] or _G[prefix .. STANCE_HOLD_DEFAULT:upper()]
	end

	function ENT:NSTakeStance()
		self.NSStance = STANCE_CROUCHED
		self:AddGesture(HoldAct("ACT_HL2MP_GESTURE_RELOAD_", HoldType(self)))
	end

	-- Seated on the cart: the sitting pose, whatever DrGBase would play; a
	-- loser on its feet (WS.IsLoser): the loser state's, scared standing
	-- and panicked on the move, as a player's (sh_core.lua); in a battle
	-- stance, its crouch.
	function ENT:OnUpdateAnimation()
		if self.NSSeated then return ACT_HL2MP_SIT, 1 end
		if WS.IsLoser(self) and self:IsOnGround() and not (self:IsDown() or self:IsDead()) then
			return self:IsMoving() and ACT_HL2MP_RUN_PANICKED or ACT_HL2MP_IDLE_SCARED, 1
		end
		if self.NSStance then return HoldAct("ACT_HL2MP_IDLE_CROUCH_", HoldType(self)), 1 end
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
		WS.PlayDeath(self:GetPos(), self.NSVoiceLines)
		if self:NSClientRagdoll(dmg) then self:PauseCoroutine(Ragdoll.HANDOFF) end
		if self.NSDormant then self:NSRest() end
	end

	-- Kept for a respawn wave (the AI war's reserve sets NSDormant as the
	-- soldier falls): after the clients' ragdoll handoff the body is hidden
	-- and not solid, and DrGBase's death coroutine waits here instead of
	-- going on to remove it, until NSRevive gives the soldier a new one.
	local function SetShown(self, shown)
		self:SetNoDraw(not shown)
		local active = self:GetActiveWeapon()
		for _, child in ipairs(self:GetChildren()) do
			child:SetNoDraw(not Arms.Drawn(shown, child:IsWeapon(), child == active))
		end
	end

	function ENT:NSRest()
		SetShown(self, false)
		self:SetNotSolid(true)
		while true do coroutine.yield() end
	end

	-- A wave revives a kept body where it spawns its soldiers: at full
	-- health, seen and solid, alive to the engine and to DrGBase, with a fresh
	-- behaviour coroutine in place of the death one. A soldier that died
	-- mid-climb or mid-leap (CustomClimbing) never reached the end where
	-- DrGBase clears those: they are cleared here, or it comes back walking
	-- in its climb animation.
	function ENT:NSRevive(pos, ang)
		self.NSDormant = nil
		self:SetPos(pos)
		self:SetAngles(ang)
		self:SetNW2Bool("DrGBaseDying", false)
		self:SetNW2Bool("DrGBaseDead", false)
		self:SetNW2Bool("DrGBaseClimbing", false)
		self:SetNW2Bool("DrGBaseClimbingDown", false)
		self:SetNW2Bool("DrGBaseJumping", false)
		self._DrGBaseClimbLadder, self.NSLeapt, self.NSLeapRetry = nil, nil, nil
		self:SetSaveValue("m_lifeState", LIFE_ALIVE)
		self:SetHealth(self:GetMaxHealth())
		self:SetNotSolid(false)
		SetShown(self, true)
		self.BehaveThread = nil
		self:BehaveStart()
	end
end

if SERVER then return end

-- Heal beams and medic calls are TF2's, drawn by ws/cl_medic_effects.lua.
