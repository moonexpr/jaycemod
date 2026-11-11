local HL2_WEAPONS =
{
	"weapon_crowbar",
	"weapon_pistol",
	"weapon_smg1",
	"weapon_frag",
	"weapon_physcannon",
	"weapon_crossbow",
	"weapon_shotgun",
	"weapon_357",
	"weapon_rpg",
	"weapon_ar2"
}

local HL2_EXTENDED_WEAPONS =
{
	"simple_hl2e_alyxgun",
	"simple_hl2e_ar1",
	"simple_hl2e_ar3",
	"simple_hl2e_ar3_sniper",
	"simple_hl2e_arp",
	"simple_hl2e_autogun",
	"simple_hl2e_crossbow_he",
	"simple_hl2e_csniper",
	"simple_hl2e_oicw"
}

local CSTRIKE_WEAPONS =
{
	"simple_css_ak47",
	"simple_css_aug",
	"simple_css_awp",
	"simple_css_deagle",
	"simple_css_elite",
	"simple_css_famas",
	"simple_css_fiveseven",
	"simple_css_flashbang",
	"simple_css_g3sg1",
	"simple_css_galil",
	"simple_css_glock",
	"simple_css_hegrenade",
	"simple_css_knife",
	"simple_css_m249",
	"simple_css_m3",
	"simple_css_m4a1",
	"simple_css_mac10",
	"simple_css_mp5",
	"simple_css_p228",
	"simple_css_p90",
	"simple_css_scout",
	"simple_css_sg550",
	"simple_css_sg552",
	"simple_css_smokegrenade",
	"simple_css_tmp",
	"simple_css_ump",
	"simple_css_usp",
	"simple_css_xm1014"
}

local BMESA_WEAPONS =
{
	"weapon_bmesa_357",
	"weapon_bmesa_crossbow",
	"weapon_bmesa_crowbar",
	"weapon_bmesa_frag",
	-- too powerful. to do: balance this weapon
	-- "weapon_bmesa_gluon",
	"weapon_bmesa_hivehand",
	"weapon_bmesa_glock",
	"weapon_bmesa_rpg",
	"weapon_bmesa_satchel",
	"weapon_bmesa_shotgun",
	"weapon_bmesa_mp5",
	"weapon_bmesa_tripmine",
	"weapon_bmesa_tau"
}

local function GiveAll (ply, classes)
	for _, class in ipairs (classes) do
		ply:Give (class)
	end
end

local function GiveHL2Ammo (ply)
	ply:GiveAmmo (256, "Pistol",       true)
	ply:GiveAmmo (256, "SMG1",         true)
	ply:GiveAmmo (5,   "SMG1_Grenade", true)
	ply:GiveAmmo (5,   "grenade",      true)
	ply:GiveAmmo (64,  "Buckshot",     true)
	ply:GiveAmmo (32,  "357",          true)
	ply:GiveAmmo (32,  "XBowBolt",     true)
	ply:GiveAmmo (6,   "AR2AltFire",   true)
	ply:GiveAmmo (100, "AR2",          true)
end

GM.SimpleWeaponLoadout =
{
	GiveBM = function (ply)
		GiveHL2Ammo (ply)
		GiveAll (ply, BMESA_WEAPONS)
	end,
	GiveHL2 = function (ply)
		GiveHL2Ammo (ply)
		GiveAll (ply, HL2_WEAPONS)
	end,
	GiveHL2AndExtended = function (ply)
		GiveHL2Ammo (ply)
		GiveAll (ply, HL2_WEAPONS)
		GiveAll (ply, HL2_EXTENDED_WEAPONS)
	end,
	GiveHL2Extended = function (ply)
		GiveHL2Ammo (ply)
		GiveAll (ply, HL2_EXTENDED_WEAPONS)
	end,
	GiveCStrike = function (ply)
		GiveAll (ply, CSTRIKE_WEAPONS)
	end,
	GiveCombatantTools = function (ply)
		ply:Give ("gmod_tool")
		ply:Give ("gmod_camera")
	end,
	GiveSandboxTools = function (ply)
		ply:Give ("weapon_physgun")
		ply:Give ("gmod_tool")
		ply:Give ("gmod_camera")
	end
}
