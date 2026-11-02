if SERVER then AddCSLuaFile() end

local WEAPONS = {
	"base_cstrike", "base_cstrike_melee", "base_cstrike_grenade",
	"weapon_glock", "weapon_usp", "weapon_p228", "weapon_deagle", "weapon_elite", "weapon_fiveseven",
	"weapon_m3", "weapon_xm1014", "weapon_mac10", "weapon_tmp", "weapon_mp5navy", "weapon_ump45", "weapon_p90",
	"weapon_galil", "weapon_famas", "weapon_ak47", "weapon_m4a1", "weapon_sg552", "weapon_aug",
	"weapon_scout", "weapon_awp", "weapon_g3sg1", "weapon_sg550", "weapon_m249",
	"weapon_knife", "weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade",
}

local ENTITIES = {
	"base_cstrike_grenade", "hegrenade_projectile", "flashbang_projectile", "smokegrenade_projectile",
}

local function IncludeWeapon(class)
	local path = "cstrike_weapons/weapons/" .. class .. ".lua"
	if SERVER then AddCSLuaFile(path) end
	local previous = SWEP
	SWEP = {}
	include(path)
	local definition = SWEP
	SWEP = previous
	weapons.Register(definition, class)
end

local function IncludeEntity(class)
	local path = "cstrike_weapons/entities/" .. class .. ".lua"
	if SERVER then AddCSLuaFile(path) end
	local previous = ENT
	ENT = {}
	include(path)
	local definition = ENT
	ENT = previous
	scripted_ents.Register(definition, class)
end

for _, class in ipairs(WEAPONS) do
	IncludeWeapon(class)
end

for _, class in ipairs(ENTITIES) do
	IncludeEntity(class)
end
