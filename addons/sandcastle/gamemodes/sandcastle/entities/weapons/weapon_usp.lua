-- weapon_usp: a standard CS:S SWEP; its base owns shared behavior.
AddCSLuaFile()

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "K&M .45 TACTICAL"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 1
SWEP.SlotPos = 1
SWEP.ViewModel = Model("models/weapons/cstrike/c_pist_usp.mdl")
SWEP.WorldModel = Model("models/weapons/w_pist_usp.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "pistol"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Pistol"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 500
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.2
SWEP.SingleShotSound = "Weapon_USP.Single"
SWEP.SpecialSound1 = "Weapon_USP.SilencedShot"
SWEP.SpecialSound2 = "Weapon_USP.DetachSilencer"
SWEP.SpecialSound3 = "Weapon_USP.AttachSilencer"
SWEP.Primary = { ClipSize = 12, DefaultClip = 12, Automatic = false, Ammo = "BULLET_PLAYER_45ACP" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 34,
		BulletCount = 1,
		CycleTime = 0.15,
		Penetration = 1,
		Range = 4096,
		RangeModifier = 0.79,
		FullAuto = false,
	},
	Accuracy = {
		Crouch = 0.006,
		Fire = 0.03495,
		Jump = 0.28725,
		Ladder = 0.01915,
		Land = 0.05745,
		Move = 0.01724,
		RecoveryCrouch = 0.23371,
		RecoveryStand = 0.28045,
		Spread = 0.004,
		Stand = 0.008,
	},
	AlternateAccuracy = {
		Fire = 0.02504,
		Jump = 0.29625,
		Ladder = 0.01975,
		Land = 0.05925,
		Move = 0.01778,
		Spread = 0.003,
	},
	Kick = {
		PunchMin = 2,
		PunchMax = 2,
	},
	Mode = {
		Type = "silencer",
	},
}
SWEP.SoldierClip = 12
SWEP.SoldierInterval = 0.15
SWEP.SoldierSpread = 0.6875163546391
SWEP.SoldierReload = 2.2
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_USP.Single"
SWEP.SoldierDamage = 34
SWEP.SoldierHoldType = "pistol"
SWEP.SoldierBullets = 1
SWEP.AIReach = 750
SWEP.AIChase = 500
SWEP.AIAvoid = 350
SWEP.AICone = 1.3750327092782
