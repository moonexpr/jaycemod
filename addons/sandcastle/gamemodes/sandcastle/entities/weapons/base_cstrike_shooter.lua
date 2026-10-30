-- weapon_cstrike_base: CS:S's guns (gameplay.cstrike_weapons), each a SWEP on this
-- base named as CS:S names it (weapon_ak47, weapon_m4a1, ...), shown by
-- GMod's c_ model of it in the player's own hands. Everything that decides
-- a shot is predicted, on both realms: the accuracy model's penalty (kept
-- with the time it was set, and recovered from it when read), the spray
-- from the command's shared random seed, recoil as the view's punch, which
-- the shot is aimed along, as CS:S aims. A bullet's damage is the model's
-- by its distance and hit group, set as it hits.
--
-- The least loved guns have a twist (Css.TWISTS), a TF2 player condition
-- each hit inflicts (WS.Inflict): the UMP-45's milks (its hurters heal), the
-- TMP's bleeds, the Five-seveN's marks for death; none stuns.
--
-- The second attack is the weapon's second mode: the M4A1's and USP's
-- silencer, the Glock's and FAMAS's burst, the scopes' zoom (a sniper rifle
-- cycling its bolt drops its scope until it may fire again). Shotguns load
-- a shell at a time, and firing stops the loading.
AddCSLuaFile()

local Css = gameplay.cstrike_weapons

SWEP.PrintName = "CS:S gun"
SWEP.Spawnable = false
SWEP.ViewModel = "models/weapons/cstrike/c_rif_ak47.mdl"
SWEP.WorldModel = "models/weapons/w_rif_ak47.mdl"
SWEP.UseHands = true
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

local EMPTY_DELAY = 0.2 -- seconds between clicks of an empty gun
local MODE_DELAY = 0.3 -- seconds between changes of mode
local MOVING = 5 -- units a second across the ground: CS:S kicks a gun moving past it as moving
local LOAD_NONE, LOAD_STARTING, LOAD_INSERTING = 0, 1, 2

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

function SWEP:CSS() return Css.WEAPONS[self.CSSClass] end

function SWEP:Mode()
	local second = self:CSS().second
	return second and second.mode or nil
end

function SWEP:Silenced() return self:Mode() == Css.SILENCER and self:GetSecond() end

-- Whether the script's second accuracy is in use: silenced, or scoped.
function SWEP:UsesSecond()
	local mode = self:Mode()
	if mode == Css.SCOPE then return self:GetZoom() > 0 and self:GetRezoom() == 0 end
	return mode == Css.SILENCER and self:GetSecond()
end

function SWEP:Model() return Css.Accuracy(self:CSS(), self:UsesSecond()) end

local function Crouching(owner) return owner:IsPlayer() and owner:Crouching() end

function SWEP:CurrentPenalty()
	return Css.Recover(self:Model(), self:GetPenalty(), Crouching(self:GetOwner()), CurTime() - self:GetPenaltyAt())
end

function SWEP:SetPenaltyNow(penalty)
	self:SetPenalty(penalty)
	self:SetPenaltyAt(CurTime())
end

-- The view model's current sequence's length, for what waits on it.
function SWEP:ViewDuration()
	local owner = self:GetOwner()
	local vm = IsValid(owner) and owner.GetViewModel and owner:GetViewModel()
	return IsValid(vm) and vm:SequenceDuration() or 0
end

function SWEP:Act(plain, silenced) return self:Silenced() and silenced or plain end

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
	self:SetPenaltyNow(Css.Base(self:Model(), false))
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

-- Firing ----------------------------------------------------------------------

function SWEP:EmptyClick()
	local w = self:CSS()
	self:EmitSound(w.type == "Pistol" and "Default.ClipEmpty_Pistol" or "Default.ClipEmpty_Rifle")
	self:SetNextPrimaryFire(CurTime() + EMPTY_DELAY)
	if self:Ammo1() > 0 then self:Reload() end
end

function SWEP:PrimaryAttack()
	if self:GetLoading() ~= LOAD_NONE then
		if self:Clip1() <= 0 then return end
		self:SetLoading(LOAD_NONE)
	end
	if self:Clip1() <= 0 then return self:EmptyClick() end
	local w = self:CSS()
	if self:Mode() == Css.BURST and self:GetSecond() then
		self:SetBurstLeft(w.second.rounds - 1)
		self:SetNextBurst(CurTime() + w.second.gap)
		self:Shoot()
		self:SetNextPrimaryFire(CurTime() + w.second.after)
		return
	end
	self:Shoot()
	self:SetNextPrimaryFire(CurTime() + w.cycle)
end

local function Random(name)
	local n = 0
	return function()
		n = n + 1
		return util.SharedRandom(name, 0, 1, n)
	end
end

-- Whether this weapon's owner may hurt victim (mp_friendlyfire), so its
-- twist touches only those its bullets may.
function SWEP:Hurts(victim)
	local owner = self:GetOwner()
	return not WS.TeamRules.FriendlySpared(WS.FriendlyFire(), WS.TeamNumber(owner), WS.TeamNumber(victim), owner == victim)
end

-- What a bullet does to victim beside its damage, on the server: tells a
-- skill shot (ws/sv_hits.lua's cap lets it kill) as it hits, and keeps
-- victim for the gun's twist (Twist).
function SWEP:Hit(victim, scoped)
	if Css.SkillShot(self:CSS(), { scoped = scoped }) then WS.SkillShot(victim) end
	if not Css.Twist(self:GetClass()) then return end
	self.wsTwisted = self.wsTwisted or {}
	self.wsTwisted[victim] = true
end

-- The gun's twist on each fighter the shot hit and may hurt, once the shot's
-- damage is dealt, as TF2 adds a hit's condition after its damage: the hit
-- that marks or milks is not itself a mini-crit or a heal.
function SWEP:Twist()
	local twisted, twist = self.wsTwisted, Css.Twist(self:GetClass())
	self.wsTwisted = nil
	if not twisted then return end
	for victim in pairs(twisted) do
		if IsValid(victim) and WS.Combatant(victim) and victim:Health() > 0 and self:Hurts(victim) then
			WS.Inflict(victim, self:GetOwner(), twist.cond, twist.seconds)
		end
	end
end

function SWEP:Shoot()
	local w, owner = self:CSS(), self:GetOwner()
	local acc, silenced = self:Model(), self:Silenced()
	local penalty = self:CurrentPenalty()
	local state = {
		penalty = penalty,
		speed = owner:GetVelocity():Length2D(),
		onGround = owner:IsOnGround(),
		ladder = owner:GetMoveType() == MOVETYPE_LADDER,
	}
	local spray = Css.Spray(Css.Inaccuracy(w, acc, state), acc.spread, w.bullets, Random("cstrike_spray"))
	local aim = owner:EyeAngles()
	if owner:IsPlayer() then aim = aim + owner:GetViewPunchAngles() end
	local forward, right, up = aim:Forward(), aim:Right(), aim:Up()
	local src = owner:GetShootPos()
	local scoped = self:Mode() == Css.SCOPE and self:GetZoom() > 0
	local callback = function(_, tr, dmginfo)
		dmginfo:SetDamage(Css.Damage(w, tr.HitPos:Distance(tr.StartPos), tr.HitGroup))
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
			Damage = w.damage,
			Distance = w.range,
			Force = w.damage * 0.1,
			Tracer = silenced and 0 or 1,
			AmmoType = w.ammo,
			Callback = callback,
		})
	end
	if owner:IsPlayer() then owner:LagCompensation(false) end
	if SERVER then self:Twist() end
	self:TakePrimaryAmmo(1)
	self:SetPenaltyNow(Css.Fired(acc, penalty))
	self:SetShots(self:GetShots() + 1)
	self:ShootAnimation(silenced)
	self:EmitSound(silenced and w.sounds.special1 or w.sounds.single_shot)
	if not silenced then owner:MuzzleFlash() end
	owner:SetAnimation(PLAYER_ATTACK1)
	if owner:IsPlayer() then self:Recoil(owner, state) end
	if self:Mode() == Css.SCOPE and self:GetZoom() > 0 and not w.fullAuto then
		self:SetRezoom(CurTime() + w.cycle)
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
	local w = self:CSS()
	local stance = (not state.onGround and Css.AIR) or (state.speed > MOVING and Css.MOVE)
		or (owner:Crouching() and Css.CROUCH) or Css.STAND
	local roll
	if w.kick.punch then
		roll = util.SharedRandom("cstrike_kick", 0, 1)
	else
		roll = math.floor(util.SharedRandom("cstrike_kick", 0, w.kick.flip + 1))
	end
	local p = owner:GetViewPunchAngles()
	local punch, left = Css.Kick(w, stance, self:GetShots(), { pitch = p.p, yaw = p.y }, self:GetKickLeft(), roll)
	self:SetKickLeft(left)
	owner:SetViewPunchAngles(Angle(punch.pitch, punch.yaw, 0))
end

-- Second modes ----------------------------------------------------------------

function SWEP:SecondaryAttack()
	local mode = self:Mode()
	if mode == nil then return end
	local owner, now = self:GetOwner(), CurTime()
	if mode == Css.SILENCER then
		local on = not self:GetSecond()
		self:SetSecond(on)
		self:SendWeaponAnim(on and ACT_VM_ATTACH_SILENCER or ACT_VM_DETACH_SILENCER)
		local ready = now + self:ViewDuration()
		self:SetNextPrimaryFire(ready)
		self:SetNextSecondaryFire(ready)
	elseif mode == Css.BURST then
		local on = not self:GetSecond()
		self:SetSecond(on)
		if SERVER and owner:IsPlayer() then
			owner:PrintMessage(HUD_PRINTCENTER, on and "Switched to burst-fire mode"
				or (self:CSS().fullAuto and "Switched to full auto" or "Switched to semi-automatic"))
		end
		self:SetNextSecondaryFire(now + MODE_DELAY)
	else
		self:SetZoom((self:GetZoom() + 1) % (#self:CSS().second.fov + 1))
		self:SetRezoom(0)
		self:ApplyZoom()
		self:EmitSound("Default.Zoom")
		self:SetNextSecondaryFire(now + MODE_DELAY)
	end
end

function SWEP:ApplyZoom()
	local owner = self:GetOwner()
	if not (IsValid(owner) and owner:IsPlayer()) then return end
	local level = self:GetRezoom() == 0 and self:GetZoom() or 0
	owner:SetFOV(level > 0 and self:CSS().second.fov[level] or 0, 0.1)
end

function SWEP:Unzoom()
	if self:Mode() ~= Css.SCOPE then return end
	self:SetZoom(0)
	self:SetRezoom(0)
	self:ApplyZoom()
end

-- Reloading -------------------------------------------------------------------

function SWEP:Reload()
	local w, owner = self:CSS(), self:GetOwner()
	if self:Clip1() >= w.clip or self:Ammo1() <= 0 then return end
	if self:GetLoading() ~= LOAD_NONE or self:GetBurstLeft() > 0 or self:GetNextPrimaryFire() > CurTime() then return end
	self:Unzoom()
	if w.type == "Shotgun" then
		self:SetLoading(LOAD_STARTING)
		self:SendWeaponAnim(ACT_SHOTGUN_RELOAD_START)
		self:SetLoadAt(CurTime() + self:ViewDuration())
		owner:SetAnimation(PLAYER_RELOAD)
		return
	end
	if self:DefaultReload(self:Act(ACT_VM_RELOAD, ACT_VM_RELOAD_SILENCED)) then self:SetShots(0) end
end

-- A shotgun's loading: started, then a shell a turn of the insert, then
-- finished when full or out of shells.
function SWEP:Load(now)
	local loading = self:GetLoading()
	if loading == LOAD_NONE or now < self:GetLoadAt() then return end
	local owner, ammo = self:GetOwner(), self:GetPrimaryAmmoType()
	if loading == LOAD_INSERTING then
		self:SetClip1(self:Clip1() + 1)
		owner:RemoveAmmo(1, ammo)
	end
	if self:Clip1() >= self:CSS().clip or owner:GetAmmoCount(ammo) <= 0 then
		self:SetLoading(LOAD_NONE)
		self:SendWeaponAnim(ACT_SHOTGUN_RELOAD_FINISH)
		self:SetNextPrimaryFire(now + self:ViewDuration())
		return
	end
	self:SetLoading(LOAD_INSERTING)
	self:SendWeaponAnim(ACT_VM_RELOAD)
	self:SetLoadAt(now + self:ViewDuration())
end

-- Each tick -------------------------------------------------------------------

function SWEP:Think()
	local owner = self:GetOwner()
	if not IsValid(owner) or not owner:IsPlayer() then return end
	local now = CurTime()
	local grounded = owner:IsOnGround()
	if grounded and not self:GetGrounded() then self:SetPenaltyNow(Css.Landed(self:Model(), self:CurrentPenalty())) end
	self:SetGrounded(grounded)
	if self:GetBurstLeft() > 0 and now >= self:GetNextBurst() then
		if self:Clip1() > 0 then
			self:Shoot()
			self:SetBurstLeft(self:GetBurstLeft() - 1)
			self:SetNextBurst(now + self:CSS().second.gap)
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

-- The scope -------------------------------------------------------------------

if CLIENT then
	local ARC = Material("sprites/scope_arc")

	-- A sniper rifle's scope covers the view, its gun hidden; a rifle's
	-- zoom does not.
	function SWEP:Scoped()
		return self:CSS().type == "SniperRifle" and self:GetZoom() > 0 and self:GetRezoom() == 0
	end

	function SWEP:PreDrawViewModel()
		return self:Scoped()
	end

	function SWEP:AdjustMouseSensitivity()
		if self:GetZoom() == 0 or self:GetRezoom() > 0 then return nil end
		return self:CSS().second.fov[self:GetZoom()] / LocalPlayer():GetInfoNum("fov_desired", 90)
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
