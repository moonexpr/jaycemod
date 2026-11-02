-- weapon_knife: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike_melee"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "KNIFE"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 2
SWEP.SlotPos = 1
SWEP.ViewModel = Model("models/weapons/cstrike/c_knife_t.mdl")
SWEP.WorldModel = Model("models/weapons/w_knife_t.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "knife"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Knife"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 0
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadSound = "Default.Reload"
SWEP.EmptySound = "Default.ClipEmpty_Rifle"
SWEP.SingleShotSound = "Weapon_DEagle.Single"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = true, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = true, Ammo = "none" }
SWEP.StabReach = 32
SWEP.StabDamage = 65
SWEP.StabInterval = 1
SWEP.SlashFreshWindow = 0.4
SWEP.SlashReach = 48
SWEP.SlashDamage = 15
SWEP.SlashFirstDamage = 20
SWEP.SlashInterval = 0.4
SWEP.BackstabMultiplier = 3
SWEP.BackstabDot = 0.8
SWEP.AIAutomatic = true
SWEP.AIInterval = 0.4
SWEP.AIDamage = 15
SWEP.AIMelee = true
