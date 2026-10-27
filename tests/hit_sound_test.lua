local T = dofile("tests/harness.lua")
local HitSound = T.require("games.gameplay.combat.hit_sound")

-- tf_dingalingaling_effect's list, in TF2's order (cfg/user.scr).
T.test("each hit sound effect is TF2's sound for it", function()
	T.eq(HitSound.Sound(0, ""), "Player.HitSoundDefaultDing", "Default")
	T.eq(HitSound.Sound(1, ""), "Player.HitSoundElectro", "Electro")
	T.eq(HitSound.Sound(8, ""), "Player.HitSoundSquasher", "Squasher")
	T.eq(#HitSound.EFFECTS, 9, "Default to Squasher")
end)

T.test("a wav override plays in place of the effect", function()
	T.eq(HitSound.Sound(3, "ui/my_ding.wav"), "ui/my_ding.wav", "the override")
end)

-- tf_dingaling_pitchmindmg at the least damage, pitchmaxdmg at the most.
T.test("the pitch follows the damage between its two settings", function()
	T.eq(HitSound.Pitch(HitSound.LOW_DAMAGE, 50, 150), 50, "least damage")
	T.eq(HitSound.Pitch(HitSound.HIGH_DAMAGE, 50, 150), 150, "most damage")
	T.eq(HitSound.Pitch((HitSound.LOW_DAMAGE + HitSound.HIGH_DAMAGE) / 2, 50, 150), 100, "between")
	T.eq(HitSound.Pitch(1, 50, 150), 50, "below the least")
	T.eq(HitSound.Pitch(1000, 50, 150), 150, "above the most")
	T.eq(HitSound.Pitch(75, 100, 100), 100, "TF2's default: one pitch")
end)

-- tf_dingalingaling_repeat_delay: 0 plays for every hit.
T.test("a hit sound waits out the repeat delay after the last", function()
	T.eq(HitSound.Ready(nil, 0, 0.5), true, "the first")
	T.eq(HitSound.Ready(1, 1.2, 0.5), false, "too soon")
	T.eq(HitSound.Ready(1, 1.5, 0.5), true, "waited")
	T.eq(HitSound.Ready(1, 1, 0), true, "no delay")
end)

-- The hit sound plays as a file, so its pitch (by damage) and volume are
-- ours: played by name, a soundscript's own would override them.
T.test("a hit sound's files: a soundscript's one or many, or a path as itself", function()
	T.eq(table.concat(HitSound.Files("Player.HitSoundBeepo", "ui/hitsound_beepo.wav"), " "), "ui/hitsound_beepo.wav", "one")
	T.eq(table.concat(HitSound.Files("Player.HitSoundNotes", { "ui/hitsound_menu_note1.wav", "ui/hitsound_menu_note2.wav" }), " "),
		"ui/hitsound_menu_note1.wav ui/hitsound_menu_note2.wav", "many")
	T.eq(table.concat(HitSound.Files("ui/my_ding.wav", nil), " "), "ui/my_ding.wav", "an override, no soundscript")
end)

T.finish()
