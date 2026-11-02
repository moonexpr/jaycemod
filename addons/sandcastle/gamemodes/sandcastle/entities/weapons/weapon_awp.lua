-- weapon_awp: a standard CS:S SWEP; its base owns shared behavior.
AddCSLuaFile()

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "MAGNUM SNIPER RIFLE"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_snip_awp.mdl")
SWEP.WorldModel = Model("models/weapons/w_snip_awp.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = false
SWEP.CStrikeType = "SniperRifle"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 4750
SWEP.MaxPlayerSpeed = 210
SWEP.ReloadTime = 3.5
SWEP.SingleShotSound = "Weapon_AWP.Single"
SWEP.SpecialSound3 = "Default.Zoom"
SWEP.Primary = { ClipSize = 10, DefaultClip = 10, Automatic = false, Ammo = "BULLET_PLAYER_338MAG" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 115,
		BulletCount = 1,
		CycleTime = 1.5,
		Penetration = 3,
		Range = 8192,
		RangeModifier = 0.99,
		FullAuto = false,
	},
	Accuracy = {
		Crouch = 0.0606,
		Fire = 0.14,
		Jump = 0.546,
		Ladder = 0.1365,
		Land = 0.0546,
		Move = 0.273,
		RecoveryCrouch = 0.24671,
		RecoveryStand = 0.34539,
		Spread = 0.0002,
		Stand = 0.0808,
	},
	AlternateAccuracy = {
		Crouch = 0.0015,
		Stand = 0.002,
	},
	Kick = {
		PunchMin = 2,
		PunchMax = 2,
	},
	Mode = {
		Type = "scope",
		Speed = 150,
		FOV = { 40, 10 },
	},
}
SWEP.SoldierClip = 10
SWEP.SoldierInterval = 1.5
SWEP.SoldierSpread = 4.6308481344137
SWEP.SoldierReload = 3.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_AWP.Single"
SWEP.SoldierDamage = 115
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIReach = 3000
SWEP.AIChase = 2000
SWEP.AIAvoid = 750
SWEP.AICone = 9.2616962688273
