-- The Scout's Scattergun, in the player's own hands
AddCSLuaFile ()

SWEP.Base      = "tf_weapon_base"
SWEP.PrintName = "Scattergun"
SWEP.Spawnable = true
SWEP.Slot      = 2
SWEP.HoldType  = "shotgun"

SWEP.ViewModel  = "models/weapons/c_models/c_scout_arms.mdl"
SWEP.TFModel    = "models/weapons/c_models/c_scattergun.mdl"
SWEP.WorldModel = SWEP.TFModel

-- c_scout_animations.mdl's, by activity (docs/tf2-hands-spike.md)
SWEP.TFAnimations =
{
	draw        = "ACT_PRIMARY_VM_DRAW",
	idle        = "ACT_PRIMARY_VM_IDLE",
	fire        = "ACT_PRIMARY_VM_PRIMARYATTACK",
	reloadStart = "ACT_PRIMARY_RELOAD_START",
	reload      = "ACT_PRIMARY_VM_RELOAD",
	reloadEnd   = "ACT_PRIMARY_RELOAD_FINISH"
}
SWEP.TFReloadsSingly = true

-- TF2's tf_weapon_scattergun
SWEP.Primary.ClipSize    = 6
SWEP.Primary.DefaultClip = 38
SWEP.Primary.Ammo        = "Buckshot"
SWEP.Primary.Damage      = 6
SWEP.Primary.Bullets     = 10
SWEP.Primary.Spread      = 0.0675
SWEP.Primary.Delay       = 0.625
SWEP.Primary.Sound       = "weapons/scatter_gun_shoot.wav"
SWEP.DeployTime          = 0.5

-- Third person: the Scout's player animations, on the player's own model (body_rig.py, rig_gate.py --third)
SWEP.TFPlayerModel = "models/player/scout.mdl"
SWEP.TFPlayerAnimations =
{
	stand       = "ACT_MP_STAND_PRIMARY",
	crouch      = "ACT_MP_CROUCH_PRIMARY",
	run         = "ACT_MP_RUN_PRIMARY",
	crouchWalk  = "ACT_MP_CROUCHWALK_PRIMARY",
	swim        = "ACT_MP_SWIM_PRIMARY",
	air         = "ACT_MP_AIRWALK_PRIMARY",
	attack      = "ACT_MP_ATTACK_STAND_PRIMARY",
	reloadStart = "ACT_MP_RELOAD_STAND_PRIMARY",
	reload      = "ACT_MP_RELOAD_STAND_PRIMARY_LOOP",
	reloadEnd   = "ACT_MP_RELOAD_STAND_PRIMARY_END"
}
