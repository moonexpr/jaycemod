AddCSLuaFile()

-- weapon_elite: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = ".40 DUAL ELITES"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 1
SWEP.SlotPos = 1
SWEP.ViewModel = Model("models/weapons/cstrike/c_pist_elite.mdl")
SWEP.WorldModel = Model("models/weapons/w_pist_elite.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "duel"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Pistol"
SWEP.CStrikeTeam = "TERRORIST"
SWEP.Price = 800
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.2
SWEP.SingleShotSound = "Weapon_Elite.Single"
SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = false, Ammo = "BULLET_PLAYER_9MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 45,
		BulletCount = 1,
		CycleTime = 0.12,
		Penetration = 1,
		Range = 4096,
		RangeModifier = 0.75,
		FullAuto = false,
	},
	Accuracy = {
		Crouch = 0.006,
		Fire = 0.03162,
		Jump = 0.29625,
		Ladder = 0.01975,
		Land = 0.05925,
		Move = 0.01778,
		RecoveryCrouch = 0.24753,
		RecoveryStand = 0.29703,
		Spread = 0.004,
		Stand = 0.008,
	},
	Kick = {
		PunchMin = 1.5,
		PunchMax = 1.5,
	},
}
SWEP.SoldierClip = 30
SWEP.SoldierInterval = 0.12
SWEP.SoldierSpread = 0.6875163546391
SWEP.SoldierReload = 2.2
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_Elite.Single"
SWEP.SoldierDamage = 45
SWEP.SoldierHoldType = "duel"
SWEP.SoldierBullets = 1
SWEP.AIReach = 750
SWEP.AIChase = 500
SWEP.AIAvoid = 350
SWEP.AICone = 1.3750327092782
