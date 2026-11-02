-- weapon_ump45: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "K&M UMP45"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_smg_ump45.mdl")
SWEP.WorldModel = Model("models/weapons/w_smg_ump45.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "smg"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "SubMachinegun"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 1700
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.6
SWEP.SingleShotSound = "Weapon_UMP45.Single"
SWEP.Primary = { ClipSize = 25, DefaultClip = 25, Automatic = true, Ammo = "BULLET_PLAYER_45ACP" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 30,
		BulletCount = 1,
		CycleTime = 0.105,
		Penetration = 1,
		Range = 4096,
		RangeModifier = 0.82,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.01439,
		Fire = 0.01129,
		Jump = 0.16941,
		Ladder = 0.04235,
		Land = 0.03388,
		Move = 0.01366,
		RecoveryCrouch = 0.2171,
		RecoveryStand = 0.30394,
		Spread = 0.001,
		Stand = 0.01919,
	},
	Kick = {
		UpBase = 0.45,
		LateralBase = 0.3,
		UpModifier = 0.2,
		LateralModifier = 0.03,
		UpMax = 3,
		LateralMax = 2.5,
		Flip = 10,
	},
}
SWEP.TwistCondition = 27
SWEP.TwistDuration = 3
SWEP.SoldierClip = 25
SWEP.SoldierInterval = 0.105
SWEP.SoldierSpread = 1.1566446420793
SWEP.SoldierReload = 2.6
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_UMP45.Single"
SWEP.SoldierDamage = 30
SWEP.SoldierHoldType = "smg"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1000
SWEP.AIChase = 700
SWEP.AIAvoid = 500
SWEP.AICone = 2.3132892841586
