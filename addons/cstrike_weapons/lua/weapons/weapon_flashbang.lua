AddCSLuaFile()

-- weapon_flashbang: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike_grenade"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "FLASHBANG"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 3
SWEP.SlotPos = 2
SWEP.ViewModel = Model("models/weapons/cstrike/c_eq_flashbang.mdl")
SWEP.WorldModel = Model("models/weapons/w_eq_flashbang.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "grenade"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Grenade"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 200
SWEP.MaxPlayerSpeed = 250
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.GrenadeSpeed = 750
SWEP.GrenadeBlind = 4.9
SWEP.GrenadeFuse = 1.5
SWEP.GrenadeProjectile = "flashbang_projectile"
SWEP.GrenadeRadius = 1500
