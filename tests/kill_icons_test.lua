-- foundation.kill_icons: TF2's kill icons (scripts/mod_textures.txt's
-- entries on its HUD/d_images sheets) and which one a kill shows.
local T = dofile("tests/harness.lua")
local Icons = T.require("foundation.kill_icons")

local TEXTURES = [["sprites/640_hud"
{
	TextureData
	{
		"smg"
		{
				"dfile"	"HUD/d_images"
				"dnegfile"	"HUD/dneg_images"
				"x"		"0"
				"y"		"128"
				"width"		"96"
				"height"	"32"
		}
		"skull_tf"
		{
				"dfile"	"HUD/d_images"
				"dnegfile"	"HUD/dneg_images"
				"x"		"116"
				"y"		"288"
				"width"		"52"
				"height"	"32"
		}
		"tf_projectile_rocket"
		{
				"dfile"	"HUD/d_images"
				"dnegfile"	"HUD/dneg_images"
				"x"		"0"
				"y"		"224"
				"width"		"96"
				"height"	"32"
		}
		"ammo_45"
		{
				"file"	"sprites/640hud1"
				"x"		"182"
				"y"		"0"
				"width"		"26"
				"height"	"24"
		}
	}
}]]

T.test("the kill icons are the entries with a death sheet, each with its place on it", function()
	local icons = Icons.Parse(TEXTURES)
	local smg = icons.smg
	T.eq(smg.file, "HUD/d_images", "its sheet")
	T.eq(smg.negative, "HUD/dneg_images", "its dark sheet")
	T.eq(smg.x .. " " .. smg.y .. " " .. smg.w .. " " .. smg.h, "0 128 96 32", "its place")
	T.eq(icons.ammo_45, nil, "an ammo sprite is no kill icon")
end)

-- Sandcastle's own sheet (scripts/sandcastle_kill_icons.txt): HL2's
-- weapons, by class.
local OWN = [["sandcastle/kill_icons"
{
	TextureData
	{
		"weapon_smg1"
		{
			"dfile"	"sandcastle/kill_icons/hl2.png"
			"dnegfile"	"sandcastle/kill_icons/hl2_neg.png"
			"x"	"0"
			"y"	"0"
			"width"	"166"
			"height"	"64"
		}
		"weapon_rpg"
		{
			"dfile"	"sandcastle/kill_icons/hl2.png"
			"dnegfile"	"sandcastle/kill_icons/hl2_neg.png"
			"x"	"166"
			"y"	"0"
			"width"	"188"
			"height"	"64"
		}
	}
}]]

T.test("Sandcastle's sheet joins TF2's, its own icons on top", function()
	local icons = Icons.Over(Icons.Parse(TEXTURES), Icons.Parse(OWN))
	T.eq(icons.smg.file, "HUD/d_images", "TF2's are kept")
	T.eq(icons.weapon_smg1.file, "sandcastle/kill_icons/hl2.png", "and ours added")
	local again = Icons.Over(Icons.Parse(OWN), { weapon_smg1 = { file = "mine" } })
	T.eq(again.weapon_smg1.file, "mine", "the later sheet wins a name both have")
end)

T.test("an HL2 weapon shows its own icon, what it throws its icon too, any other the skull", function()
	local icons = Icons.Over(Icons.Parse(TEXTURES), Icons.Parse(OWN))
	T.eq(Icons.For(icons, "weapon_smg1"), icons.weapon_smg1, "HL2's SMG: its own")
	T.eq(Icons.For(icons, "grenade_ar2"), icons.weapon_smg1, "the SMG's grenade: the SMG")
	T.eq(Icons.For(icons, "rpg_missile"), icons.weapon_rpg, "HL2's rocket: the RPG")
	T.eq(Icons.For(icons, "tf_projectile_rocket"), icons.tf_projectile_rocket, "TF2's own")
	T.eq(Icons.For(icons, "prop_physics"), icons.skull_tf, "anything else: the skull")
	T.eq(Icons.For(icons, "weapon_crowbar"), icons.skull_tf, "an icon no sheet has: the skull")
end)

T.test("every alias names an icon", function()
	for class, name in pairs(Icons.HL2) do
		T.eq(type(name), "string", class)
	end
	T.eq(Icons.HL2.prop_combine_ball, "weapon_ar2", "the pulse rifle's ball: the pulse rifle")
end)

T.finish()
