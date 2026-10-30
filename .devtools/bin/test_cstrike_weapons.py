"""css_weapons.py turns CS:S's weapon scripts (KeyValues text, decrypted)
into the Lua data part games/gameplay/css_weapons/scripts.lua: each weapon's
numbers under Lua names, its accuracy and its second mode's, its sounds, and
its name in English from the game's localization."""
import pytest

from css_weapons import ScriptError, keyvalues, lua, weapon

AK47 = """WeaponData
{
	"MaxPlayerSpeed"		"221"
	"WeaponType"			"Rifle"
	"FullAuto"				1
	"WeaponPrice"			"2500"
	"WeaponArmorRatio"		"1.55"
	"Team" 				"TERRORIST"
	"PlayerAnimationExtension" 	"ak"
	// Weapon characteristics:
	"Penetration"			"2"
	"Damage"			"36"
	"Range"				"8192"
	"RangeModifier"			"0.98"
	"Bullets"			"1"
	"CycleTime"			"0.1"
	"Spread"					0.00060
	"InaccuracyCrouch"			0.00687
	"InaccuracyStand"			0.00916
	"InaccuracyJump"			0.43044
	"InaccuracyLand"			0.08609
	"InaccuracyLadder"			0.10761
	"InaccuracyFire"			0.01158
	"InaccuracyMove"			0.09222
	"RecoveryTimeCrouch"		0.34868
	"RecoveryTimeStand"			0.48815
	"printname"			"#Cstrike_WPNHUD_AK47"
	"viewmodel"			"models/weapons/v_rif_ak47.mdl"
	"playermodel"			"models/weapons/w_rif_ak47.mdl"
	"bucket"			"0"
	"bucket_position"		"0"
	"clip_size"			"30"
	"primary_ammo"			"BULLET_PLAYER_762MM"
	SoundData
	{
		"single_shot"		"Weapon_AK47.Single"
	}
	TextureData
	{
		"weapon"
		{
				"font"		"CSweaponsSmall"
				"character"	"B"
		}
	}
}
"""

NAMES = {"Cstrike_WPNHUD_AK47": "CV-47"}


def test_keyvalues_reads_nested_blocks_quoted_and_bare_values():
    data = keyvalues(AK47)
    assert data["WeaponData"]["FullAuto"] == "1"
    assert data["WeaponData"]["Spread"] == "0.00060"
    assert data["WeaponData"]["SoundData"]["single_shot"] == "Weapon_AK47.Single"
    assert data["WeaponData"]["TextureData"]["weapon"]["character"] == "B"


def test_a_weapon_takes_its_numbers_and_its_name():
    w = weapon("weapon_ak47", keyvalues(AK47), NAMES)
    assert w["name"] == "CV-47"
    assert w["price"] == 2500 and w["damage"] == 36 and w["clip"] == 30
    assert w["cycle"] == pytest.approx(0.1)
    assert w["fullAuto"] is True
    assert w["accuracy"]["move"] == pytest.approx(0.09222)
    assert "alt" not in w
    assert w["sounds"] == {"single_shot": "Weapon_AK47.Single"}


def test_a_script_without_weapon_data_is_refused():
    with pytest.raises(ScriptError):
        weapon("weapon_x", keyvalues('Other { "a" "1" }'), NAMES)


def test_lua_writes_a_table_in_key_order():
    assert lua({"b": 1, "a": "x", "c": {"d": True}}) == '{\n\ta = "x",\n\tb = 1,\n\tc = {\n\t\td = true,\n\t},\n}'
