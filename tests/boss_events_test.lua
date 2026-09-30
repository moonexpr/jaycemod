local T = dofile("tests/harness.lua")
local BossEvents = T.require("foundation.npc.boss_events")

-- What a client plays and prints for each boss event (ClientModeTFNormal::
-- FireGameEvent, clientmode_tf.cpp), with tf_english.txt's words.

local function Cue(name, fields)
	return BossEvents.Cue(name, fields or {})
end

T.test("the Horsemann's rise plays its music and says it appeared", function()
	local cue = Cue(BossEvents.PUMPKIN_LORD_SUMMONED)
	T.eq(cue.sound, "Halloween.HeadlessBossSpawn", "music")
	T.eq(cue.text, "The Horseless Headless Horsemann has appeared!", "text")
end)

T.test("the Horsemann's death plays its sting and says it was defeated", function()
	local cue = Cue(BossEvents.PUMPKIN_LORD_KILLED)
	T.eq(cue.sound, "Halloween.HeadlessBossDeath", "sting")
	T.eq(cue.text, "The Horseless Headless Horsemann has been defeated!", "text")
end)

T.test("MONOCULUS's rise plays its music; past the first level the text names the level", function()
	local first = Cue(BossEvents.EYEBALL_BOSS_SUMMONED, { level = BossEvents.FIRST_LEVEL })
	T.eq(first.sound, "Halloween.MonoculusBossSpawn", "music")
	T.eq(first.text, "Beware! MONOCULUS! is lurking about...", "level 1")
	T.eq(Cue(BossEvents.EYEBALL_BOSS_SUMMONED, { level = 3 }).text, "Beware! MONOCULUS! (LEVEL 3) is lurking about...", "level 3")
end)

T.test("MONOCULUS's death and escape play their lines and say so", function()
	local killed = Cue(BossEvents.EYEBALL_BOSS_KILLED, { level = 1 })
	T.eq(killed.sound, "Halloween.MonoculusBossDeath", "death")
	T.eq(killed.text, "MONOCULUS! has been defeated!", "killed")
	T.eq(Cue(BossEvents.EYEBALL_BOSS_KILLED, { level = 2 }).text, "MONOCULUS! (LEVEL 2) has been defeated!", "levelled")
	local escaped = Cue(BossEvents.EYEBALL_BOSS_ESCAPED, { level = 1 })
	T.eq(escaped.sound, "Halloween.EyeballBossEscaped", "escaped")
	T.eq(escaped.text, "MONOCULUS! has left to haunt another realm!", "escaped text")
	T.eq(Cue(BossEvents.EYEBALL_BOSS_ESCAPED, { level = 4 }).text, "MONOCULUS! (LEVEL 4) has left to haunt another realm!", "levelled")
end)

T.test("escape warnings: 10 s or less is imminent, more is soon; the text counts the seconds", function()
	local IMMINENT = BossEvents.EYEBALL_BOSS_ESCAPE_IMMINENT
	local sixty = Cue(IMMINENT, {
		level = 1,
		time_remaining = 60,
	})
	T.eq(sixty.sound, "Halloween.EyeballBossEscapeSoon", "soon")
	T.eq(sixty.text, "MONOCULUS! is leaving in 60 seconds...", "60")
	local thirty = Cue(IMMINENT, {
		level = 1,
		time_remaining = 30,
	})
	T.eq(thirty.sound, "Halloween.EyeballBossEscapeSoon", "soon")
	T.eq(thirty.text, "MONOCULUS! is leaving in 30 seconds...", "30")
	local ten = Cue(IMMINENT, {
		level = 2,
		time_remaining = 10,
	})
	T.eq(ten.sound, "Halloween.EyeballBossEscapeImminent", "imminent")
	T.eq(ten.text, "MONOCULUS! (LEVEL 2) is leaving in 10 seconds!", "10, levelled")
end)

T.test("MONOCULUS's words are in its colour, the Horsemann's in the plain chat colour", function()
	T.eq(Cue(BossEvents.EYEBALL_BOSS_KILLED, { level = 1 }).color, BossEvents.EYEBALL_COLOR, "eyeball")
	T.eq(Cue(BossEvents.PUMPKIN_LORD_KILLED).color, nil, "horsemann")
end)

T.test("every boss event has a cue", function()
	for _, name in ipairs(BossEvents.NAMES) do
		T.eq(type(BossEvents.Cue(name, {
			level = 1,
			time_remaining = 10,
		}).sound), "string", name)
	end
end)

T.finish()
