-- Shared CS:S firearm behavior. Each terminal SWEP owns its grouped stats.

SWEP.PrintName = "CS:S firearm"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = false
SWEP.CStrikeWeapon = true
SWEP.DrawAmmo = true
SWEP.UseHands = true

local AMMO = {
	BULLET_PLAYER_50AE = 35,
	BULLET_PLAYER_762MM = 90,
	BULLET_PLAYER_556MM = 90,
	BULLET_PLAYER_556MM_BOX = 200,
	BULLET_PLAYER_338MAG = 30,
	BULLET_PLAYER_9MM = 120,
	BULLET_PLAYER_BUCKSHOT = 32,
	BULLET_PLAYER_45ACP = 100,
	BULLET_PLAYER_357SIG = 52,
	BULLET_PLAYER_57MM = 100,
}

for name, maxcarry in pairs(AMMO) do
	game.AddAmmoType({ name = name, dmgtype = DMG_BULLET, tracer = TRACER_LINE_AND_WHIZ, maxcarry = maxcarry })
end

local EMPTY_DELAY, MODE_DELAY = 0.2, 0.3
local MOVING = 5
local LOAD_NONE, LOAD_STARTING, LOAD_INSERTING = 0, 1, 2
local SILENCER, BURST, SCOPE = "silencer", "burst", "scope"
local STANCES = { stand = 1, crouch = 0.9, move = 1.5, air = 2 }
local HITGROUPS = {
	[HITGROUP_GENERIC] = 1,
	[HITGROUP_HEAD] = 4,
	[HITGROUP_CHEST] = 1,
	[HITGROUP_STOMACH] = 1.25,
	[HITGROUP_LEFTARM] = 1,
	[HITGROUP_RIGHTARM] = 1,
	[HITGROUP_LEFTLEG] = 0.75,
	[HITGROUP_RIGHTLEG] = 0.75,
	[HITGROUP_GEAR] = 1,
}
local TENTH = math.log(10)

local function Clamp(value, low, high)
	return math.max(low, math.min(value, high))
end

function SWEP:SetupDataTables()
	self:NetworkVar("Float", 0, "Penalty")
	self:NetworkVar("Float", 1, "PenaltyAt")
	self:NetworkVar("Float", 2, "NextBurst")
	self:NetworkVar("Float", 3, "LoadAt")
	self:NetworkVar("Float", 4, "Rezoom")
	self:NetworkVar("Int", 0, "Shots")
	self:NetworkVar("Int", 1, "Zoom")
	self:NetworkVar("Int", 2, "BurstLeft")
	self:NetworkVar("Int", 3, "Loading")
	self:NetworkVar("Bool", 0, "Second")
	self:NetworkVar("Bool", 1, "KickLeft")
	self:NetworkVar("Bool", 2, "Grounded")
end

function SWEP:Mode()
	return self.Stats.Mode and self.Stats.Mode.Type
end

function SWEP:GetMaxSpeed()
	local mode = self.Stats.Mode
	if self:Mode() == SCOPE and self:GetZoom() > 0 and self:GetRezoom() == 0 and mode.Speed then
		return mode.Speed
	end
	return self.MaxPlayerSpeed
end

function SWEP:Silenced()
	return self:Mode() == SILENCER and self:GetSecond()
end

function SWEP:UsesSecondAccuracy()
	local mode = self:Mode()
	if mode == SCOPE then return self:GetZoom() > 0 and self:GetRezoom() == 0 end
	return mode == SILENCER and self:GetSecond()
end

function SWEP:AccuracyValue(name)
	local alternate = self.Stats.AlternateAccuracy
	local value
	if self:UsesSecondAccuracy() and alternate then value = alternate[name] end
	if value ~= nil then return value end
	return self.Stats.Accuracy[name]
end

function SWEP:BaseAccuracy(crouching)
	return crouching and self:AccuracyValue("Crouch") or self:AccuracyValue("Stand")
end

function SWEP:CurrentPenalty()
	local crouching = self:GetOwner():IsPlayer() and self:GetOwner():Crouching()
	local base = self:BaseAccuracy(crouching)
	local duration = crouching and self:AccuracyValue("RecoveryCrouch") or self:AccuracyValue("RecoveryStand")
	local elapsed = CurTime() - self:GetPenaltyAt()
	return base + (self:GetPenalty() - base) * math.exp(-elapsed * TENTH / duration)
end

function SWEP:SetPenaltyNow(penalty)
	self:SetPenalty(penalty)
	self:SetPenaltyAt(CurTime())
end

function SWEP:ViewDuration()
	local owner = self:GetOwner()
	local vm = IsValid(owner) and owner.GetViewModel and owner:GetViewModel()
	return IsValid(vm) and vm:SequenceDuration() or 0
end

function SWEP:Act(plain, silenced)
	return self:Silenced() and silenced or plain
end

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
	self:SetHoldType(self.HoldType)
	self:SetShots(0)
	self:SetZoom(0)
	self:SetRezoom(0)
	self:SetBurstLeft(0)
	self:SetLoading(LOAD_NONE)
	self:SetPenaltyNow(self:BaseAccuracy(false))
	self:SendWeaponAnim(self:Act(ACT_VM_DRAW, ACT_VM_DRAW_SILENCED))
	local ready = CurTime() + self:ViewDuration()
	self:SetNextPrimaryFire(ready)
	self:SetNextSecondaryFire(ready)
	return true
end

function SWEP:Holster()
	self:Unzoom()
	self:SetLoading(LOAD_NONE)
	self:SetBurstLeft(0)
	return true
end

function SWEP:OnRemove()
	if IsValid(self:GetOwner()) then self:Unzoom() end
end

function SWEP:EmptyClick()
	self:EmitSound(self.CStrikeType == "Pistol" and "Default.ClipEmpty_Pistol" or "Default.ClipEmpty_Rifle")
	self:SetNextPrimaryFire(CurTime() + EMPTY_DELAY)
	if self:Ammo1() > 0 then self:Reload() end
end

function SWEP:PrimaryAttack()
	if self:GetLoading() ~= LOAD_NONE then
		if self:Clip1() <= 0 then return end
		self:SetLoading(LOAD_NONE)
	end
	if self:Clip1() <= 0 then return self:EmptyClick() end
	if self:Mode() == BURST and self:GetSecond() then
		local burst = self.Stats.Mode.Burst
		self:SetBurstLeft(burst.Rounds - 1)
		self:SetNextBurst(CurTime() + burst.Gap)
		self:Shoot()
		self:SetNextPrimaryFire(CurTime() + burst.After)
		return
	end
	self:Shoot()
	self:SetNextPrimaryFire(CurTime() + self.Stats.Ballistics.CycleTime)
end

local function Random(name)
	local n = 0
	return function()
		n = n + 1
		return util.SharedRandom(name, 0, 1, n)
	end
end

function SWEP:Hurts(victim)
	local owner = self:GetOwner()
	return not WS.TeamRules.FriendlySpared(WS.FriendlyFire(), WS.TeamNumber(owner), WS.TeamNumber(victim), owner == victim)
end

function SWEP:Hit(victim, scoped)
	if self.CStrikeType == "SniperRifle" and scoped and not self.Primary.Automatic then WS.SkillShot(victim) end
	if not self.TwistCondition then return end
	self.wsTwisted = self.wsTwisted or {}
	self.wsTwisted[victim] = true
end

function SWEP:Twist()
	local twisted = self.wsTwisted
	self.wsTwisted = nil
	if not twisted then return end
	for victim in pairs(twisted) do
		if IsValid(victim) and WS.Combatant(victim) and victim:Health() > 0 and self:Hurts(victim) then
			WS.Inflict(victim, self:GetOwner(), self.TwistCondition, self.TwistDuration)
		end
	end
end

function SWEP:Inaccuracy(state)
	local speed = self.MaxPlayerSpeed
	local moving = Clamp((state.speed - speed * 0.34) / (speed * (0.95 - 0.34)), 0, 1)
	local inaccuracy = state.penalty
	if moving > 0 then inaccuracy = inaccuracy + moving ^ 0.25 * self:AccuracyValue("Move") end
	if not state.onGround then inaccuracy = inaccuracy + self:AccuracyValue("Jump") end
	if state.ladder then inaccuracy = inaccuracy + self:AccuracyValue("Ladder") end
	return math.min(inaccuracy, 1)
end

function SWEP:Spray(inaccuracy)
	local random, result = Random("cstrike_spray"), {}
	local theta, radius = random() * 2 * math.pi, random() * inaccuracy
	local x0, y0 = radius * math.cos(theta), radius * math.sin(theta)
	local spread = self:AccuracyValue("Spread")
	for i = 1, self.Stats.Ballistics.BulletCount do
		local angle, length = random() * 2 * math.pi, random() * spread
		result[i] = { x = x0 + length * math.cos(angle), y = y0 + length * math.sin(angle) }
	end
	return result
end

function SWEP:DamageAt(distance, hitgroup)
	local ballistics = self.Stats.Ballistics
	if distance > ballistics.Range then return 0 end
	return ballistics.Damage * ballistics.RangeModifier ^ (distance / 500) * (HITGROUPS[hitgroup] or 1)
end

function SWEP:Shoot()
	local owner, silenced = self:GetOwner(), self:Silenced()
	local penalty = self:CurrentPenalty()
	local state = {
		penalty = penalty,
		speed = owner:GetVelocity():Length2D(),
		onGround = owner:IsOnGround(),
		ladder = owner:GetMoveType() == MOVETYPE_LADDER,
	}
	local inaccuracy = self:Inaccuracy(state)
	local spray = self:Spray(inaccuracy)
	local aim = owner:EyeAngles()
	if owner:IsPlayer() then aim = aim + owner:GetViewPunchAngles() end
	local forward, right, up = aim:Forward(), aim:Right(), aim:Up()
	local src = owner:GetShootPos()
	local scoped = self:Mode() == SCOPE and self:GetZoom() > 0
	local ballistics = self.Stats.Ballistics
	local callback = function(_, tr, dmginfo)
		dmginfo:SetDamage(self:DamageAt(tr.HitPos:Distance(tr.StartPos), tr.HitGroup))
		if SERVER and IsValid(tr.Entity) then self:Hit(tr.Entity, scoped) end
	end
	if owner:IsPlayer() then owner:LagCompensation(true) end
	for _, offset in ipairs(spray) do
		local dir = forward + right * offset.x + up * offset.y
		dir:Normalize()
		owner:FireBullets({
			Src = src,
			Dir = dir,
			Num = 1,
			Spread = vector_origin,
			Damage = ballistics.Damage,
			Distance = ballistics.Range,
			Force = ballistics.Damage * 0.1,
			Tracer = silenced and 0 or 1,
			AmmoType = self.Primary.Ammo,
			Callback = callback,
		})
	end
	if owner:IsPlayer() then owner:LagCompensation(false) end
	if SERVER then self:Twist() end
	self:TakePrimaryAmmo(1)
	self:SetPenaltyNow(penalty + self:AccuracyValue("Fire"))
	self:SetShots(self:GetShots() + 1)
	self:ShootAnimation(silenced)
	self:EmitSound(silenced and (self.SpecialSound1 or self.SingleShotSound) or self.SingleShotSound)
	if not silenced then owner:MuzzleFlash() end
	owner:SetAnimation(PLAYER_ATTACK1)
	if owner:IsPlayer() then self:Recoil(owner, state) end
	if self:Mode() == SCOPE and self:GetZoom() > 0 and not self.Primary.Automatic then
		self:SetRezoom(CurTime() + ballistics.CycleTime)
		self:ApplyZoom()
	end
end

function SWEP:ShootAnimation(silenced)
	if self.HoldType == "duel" then
		self:SendWeaponAnim(self:Clip1() % 2 == 0 and ACT_VM_PRIMARYATTACK or ACT_VM_SECONDARYATTACK)
	else
		self:SendWeaponAnim(silenced and ACT_VM_PRIMARYATTACK_SILENCED or ACT_VM_PRIMARYATTACK)
	end
end

function SWEP:Recoil(owner, state)
	local kick = self.Stats.Kick
	local stance = (not state.onGround and "air") or (state.speed > MOVING and "move")
		or (owner:Crouching() and "crouch") or "stand"
	local scale = STANCES[stance]
	local p = owner:GetViewPunchAngles()
	local pitch, yaw = p.p, p.y
	local left = self:GetKickLeft()
	local roll
	if kick.PunchMin then
		roll = util.SharedRandom("cstrike_kick", 0, 1)
		pitch = pitch - (kick.PunchMin + (kick.PunchMax - kick.PunchMin) * roll) * scale
	else
		roll = math.floor(util.SharedRandom("cstrike_kick", 0, kick.Flip + 1))
		local extra = self:GetShots() > 1 and self:GetShots() or 0
		local up = (kick.UpBase + extra * kick.UpModifier) * scale
		local lateral = (kick.LateralBase + extra * kick.LateralModifier) * scale
		pitch = math.max(pitch - up, -kick.UpMax * scale)
		yaw = Clamp(yaw + (left and lateral or -lateral), -kick.LateralMax * scale, kick.LateralMax * scale)
		if roll == 0 then left = not left end
	end
	self:SetKickLeft(left)
	owner:SetViewPunchAngles(Angle(pitch, yaw, 0))
end

function SWEP:SecondaryAttack()
	local mode = self:Mode()
	if not mode then return end
	local owner, now = self:GetOwner(), CurTime()
	if mode == SILENCER then
		local on = not self:GetSecond()
		self:SetSecond(on)
		self:SendWeaponAnim(on and ACT_VM_ATTACH_SILENCER or ACT_VM_DETACH_SILENCER)
		local sound = on and self.SpecialSound3 or self.SpecialSound2
		if sound then self:EmitSound(sound) end
		local ready = now + self:ViewDuration()
		self:SetNextPrimaryFire(ready)
		self:SetNextSecondaryFire(ready)
	elseif mode == BURST then
		local on = not self:GetSecond()
		self:SetSecond(on)
		if SERVER and owner:IsPlayer() then
			owner:PrintMessage(HUD_PRINTCENTER, on and "Switched to burst-fire mode"
				or (self.Primary.Automatic and "Switched to full auto" or "Switched to semi-automatic"))
		end
		self:SetNextSecondaryFire(now + MODE_DELAY)
	else
		self:SetZoom((self:GetZoom() + 1) % (self:ZoomLevels() + 1))
		self:SetRezoom(0)
		self:ApplyZoom()
		self:EmitSound(self.SpecialSound3 or "Default.Zoom")
		self:SetNextSecondaryFire(now + MODE_DELAY)
	end
end

function SWEP:ZoomLevels()
	local mode = self.Stats.Mode
	return mode and mode.FOV and #mode.FOV or 0
end

function SWEP:ApplyZoom()
	local owner = self:GetOwner()
	if not (IsValid(owner) and owner:IsPlayer()) then return end
	local level = self:GetRezoom() == 0 and self:GetZoom() or 0
	owner:SetFOV(level > 0 and self.Stats.Mode.FOV[level] or 0, 0.1)
end

function SWEP:Unzoom()
	if self:Mode() ~= SCOPE then return end
	self:SetZoom(0)
	self:SetRezoom(0)
	self:ApplyZoom()
end

function SWEP:Reload()
	if self:Clip1() >= self.Primary.ClipSize or self:Ammo1() <= 0 then return end
	if self:GetLoading() ~= LOAD_NONE or self:GetBurstLeft() > 0 or self:GetNextPrimaryFire() > CurTime() then return end
	self:Unzoom()
	if self.CStrikeType == "Shotgun" then
		self:SetLoading(LOAD_STARTING)
		self:SendWeaponAnim(ACT_SHOTGUN_RELOAD_START)
		self:SetLoadAt(CurTime() + self:ViewDuration())
		self:GetOwner():SetAnimation(PLAYER_RELOAD)
		return
	end
	if self:DefaultReload(self:Act(ACT_VM_RELOAD, ACT_VM_RELOAD_SILENCED)) then self:SetShots(0) end
end

function SWEP:Load(now)
	local loading = self:GetLoading()
	if loading == LOAD_NONE or now < self:GetLoadAt() then return end
	local owner, ammo = self:GetOwner(), self:GetPrimaryAmmoType()
	if loading == LOAD_INSERTING then
		self:SetClip1(self:Clip1() + 1)
		owner:RemoveAmmo(1, ammo)
	end
	if self:Clip1() >= self.Primary.ClipSize or owner:GetAmmoCount(ammo) <= 0 then
		self:SetLoading(LOAD_NONE)
		self:SendWeaponAnim(ACT_SHOTGUN_RELOAD_FINISH)
		self:SetNextPrimaryFire(now + self:ViewDuration())
		return
	end
	self:SetLoading(LOAD_INSERTING)
	self:SendWeaponAnim(ACT_VM_RELOAD)
	self:SetLoadAt(now + self:ViewDuration())
end

function SWEP:Think()
	local owner = self:GetOwner()
	if not IsValid(owner) or not owner:IsPlayer() then return end
	local now = CurTime()
	local grounded = owner:IsOnGround()
	if grounded and not self:GetGrounded() then self:SetPenaltyNow(self:GetPenalty() + self:AccuracyValue("Land")) end
	self:SetGrounded(grounded)
	if self:GetBurstLeft() > 0 and now >= self:GetNextBurst() then
		if self:Clip1() > 0 then
			self:Shoot()
			self:SetBurstLeft(self:GetBurstLeft() - 1)
			self:SetNextBurst(now + self.Stats.Mode.Burst.Gap)
		else
			self:SetBurstLeft(0)
		end
	elseif not owner:KeyDown(IN_ATTACK) and self:GetBurstLeft() == 0 and now >= self:GetNextPrimaryFire() then
		self:SetShots(0)
	end
	if self:GetRezoom() > 0 and now >= self:GetRezoom() then
		self:SetRezoom(0)
		self:ApplyZoom()
	end
	self:Load(now)
end

if CLIENT then
	local ARC = Material("sprites/scope_arc")

	function SWEP:Scoped()
		return self.CStrikeType == "SniperRifle" and self:GetZoom() > 0 and self:GetRezoom() == 0
	end

	function SWEP:PreDrawViewModel()
		return self:Scoped()
	end

	function SWEP:AdjustMouseSensitivity()
		if self:GetZoom() == 0 or self:GetRezoom() > 0 then return nil end
		return self.Stats.Mode.FOV[self:GetZoom()] / LocalPlayer():GetInfoNum("fov_desired", 90)
	end

	function SWEP:DrawHUD()
		if not self:Scoped() then return end
		local w, h = ScrW(), ScrH()
		local size = h
		local x = (w - size) / 2
		local half = size / 2
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawRect(0, 0, x, h)
		surface.DrawRect(x + size, 0, w - x - size, h)
		surface.SetMaterial(ARC)
		surface.DrawTexturedRectUV(x, 0, half, half, 1, 1, 0, 0)
		surface.DrawTexturedRectUV(x + half, 0, half, half, 0, 1, 1, 0)
		surface.DrawTexturedRectUV(x, half, half, half, 1, 0, 0, 1)
		surface.DrawTexturedRectUV(x + half, half, half, half, 0, 0, 1, 1)
		surface.DrawLine(0, h / 2, w, h / 2)
		surface.DrawLine(w / 2, 0, w / 2, h)
	end
end
