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

T.test("an HL2 weapon shows TF2's like weapon; a TF2 one its own; any other the skull", function()
	local icons = Icons.Parse(TEXTURES)
	T.eq(Icons.For(icons, "weapon_smg1"), icons.smg, "HL2's SMG: TF2's")
	T.eq(Icons.For(icons, "rpg_missile"), icons.tf_projectile_rocket, "HL2's rocket: TF2's")
	T.eq(Icons.For(icons, "tf_projectile_rocket"), icons.tf_projectile_rocket, "TF2's own")
	T.eq(Icons.For(icons, "prop_physics"), icons.skull_tf, "anything else: the skull")
	T.eq(Icons.For(icons, "weapon_crowbar"), icons.skull_tf, "a mapped icon the sheet lacks: the skull")
end)

T.test("every HL2 weapon maps to an icon name", function()
	for class, name in pairs(Icons.HL2) do
		T.eq(type(name), "string", class)
	end
	T.eq(Icons.HL2.weapon_ar2, "pomson", "the pulse rifle: TF2's energy rifle")
end)

T.finish()
