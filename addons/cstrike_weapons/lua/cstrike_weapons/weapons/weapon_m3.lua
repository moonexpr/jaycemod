-- weapon_m3: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "LEONE 12 GAUGE SUPER"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_shot_m3super90.mdl")
SWEP.WorldModel = Model("models/weapons/w_shot_m3super90.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "shotgun"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Shotgun"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 1700
SWEP.MaxPlayerSpeed = 220
SWEP.ReloadTime = 3.5
SWEP.SingleShotSound = "Weapon_M3.Single"
SWEP.SpecialSound3 = "Default.Zoom"
SWEP.Primary = { ClipSize = 8, DefaultClip = 8, Automatic = true, Ammo = "BULLET_PLAYER_BUCKSHOT" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 26,
		BulletCount = 9,
		CycleTime = 0.88,
		Penetration = 1,
		Range = 3000,
		RangeModifier = 0.7,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.0075,
		Fire = 0.04164,
		Jump = 0.42,
		Ladder = 0.07875,
		Land = 0.084,
		Move = 0.0432,
		RecoveryCrouch = 0.29605,
		RecoveryStand = 0.41447,
		Spread = 0.04,
		Stand = 0.01,
	},
	Kick = {
		PunchMin = 4,
		PunchMax = 6,
	},
}
SWEP.SoldierClip = 8
SWEP.SoldierInterval = 0.88
SWEP.SoldierSpread = 2.8624052261117
SWEP.SoldierReload = 3.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_M3.Single"
SWEP.SoldierDamage = 26
SWEP.SoldierHoldType = "shotgun"
SWEP.SoldierBullets = 9
SWEP.AIAutomatic = true
SWEP.AIReach = 325
SWEP.AIChase = 250
SWEP.AIAvoid = 175
SWEP.AICone = 5.7248104522235
