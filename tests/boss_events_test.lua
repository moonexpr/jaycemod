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

T.test("Merasmus's arrival plays his music; past the first level the text names the level", function()
	local first = Cue(BossEvents.MERASMUS_SUMMONED, { level = BossEvents.FIRST_LEVEL })
	T.eq(first.sound, "Halloween.MerasmusBossSpawn", "music")
	T.eq(first.text, "MERASMUS! has appeared!", "level 1")
	T.eq(first.color, BossEvents.MERASMUS_COLOR, "his colour")
	T.eq(Cue(BossEvents.MERASMUS_SUMMONED, { level = 2 }).text, "MERASMUS! (LEVEL 2) has appeared!", "level 2")
end)

-- His death's music is broadcast as he starts dying (CMerasmusDying), so
-- merasmus_killed itself plays nothing.
T.test("Merasmus's defeat only says so", function()
	local killed = Cue(BossEvents.MERASMUS_KILLED, { level = 1 })
	T.eq(killed.sound, nil, "no sound")
	T.eq(killed.text, "MERASMUS! has been defeated!", "killed")
	T.eq(Cue(BossEvents.MERASMUS_KILLED, { level = 3 }).text, "MERASMUS! (LEVEL 3) has been defeated!", "levelled")
end)

-- TF_Halloween_Merasmus_Killers and _LevelUp_Killers, said in the chat for
-- each player who hit him in his last 5 s.
T.test("each of his killers is named, with his level past the first", function()
	local ply = { nick = "Soldier" }
	local function NameOf(p) return p.nick end
	local first = BossEvents.Cue(BossEvents.MERASMUS_KILLER, {
		player = ply,
		level = 1,
	}, NameOf)
	T.eq(first.text, "Soldier has defeated MERASMUS!", "named")
	T.eq(first.sound, nil, "no sound")
	T.eq(first.color, nil, "the chat's own colour")
	T.eq(BossEvents.Cue(BossEvents.MERASMUS_KILLER, {
		player = ply,
		level = 4,
	}, NameOf).text, "Soldier has defeated MERASMUS! (LEVEL 4)", "levelled")
	T.eq(BossEvents.Cue(BossEvents.MERASMUS_KILLER, {
		player = { nick = "100%d" },
		level = 2,
	}, NameOf).text, "100%d has defeated MERASMUS! (LEVEL 2)", "a % in a name is kept")
end)

T.test("Merasmus's warnings and departure use MONOCULUS's sounds and his own words", function()
	local WARNING = BossEvents.MERASMUS_ESCAPE_WARNING
	local sixty = Cue(WARNING, {
		level = 1,
		time_remaining = 60,
	})
	T.eq(sixty.sound, "Halloween.EyeballBossEscapeSoon", "soon")
	T.eq(sixty.text, "MERASMUS! is leaving in 60 seconds...", "60")
	local ten = Cue(WARNING, {
		level = 2,
		time_remaining = 10,
	})
	T.eq(ten.sound, "Halloween.EyeballBossEscapeImminent", "imminent")
	T.eq(ten.text, "MERASMUS! (LEVEL 2) is leaving in 10 seconds!", "10, levelled")
	local gone = Cue(BossEvents.MERASMUS_ESCAPED, { level = 1 })
	T.eq(gone.sound, "Halloween.EyeballBossEscaped", "escaped")
	T.eq(gone.text, "MERASMUS! has gone home!", "escaped text")
	T.eq(Cue(BossEvents.MERASMUS_ESCAPED, { level = 5 }).text, "MERASMUS! (LEVEL 5) has gone home!", "levelled")
	T.eq(BossEvents.MERASMUS_COLOR.r, 112, "colorMerasmusText")
	T.eq(BossEvents.MERASMUS_COLOR.g, 176, "colorMerasmusText")
	T.eq(BossEvents.MERASMUS_COLOR.b, 74, "colorMerasmusText")
end)

-- CTFPlayerShared's bomb stages (s_vecBombStages): the hat's skin by the
-- seconds left.
T.test("a bomb head's hat darkens through three stages as its time runs out", function()
	T.eq(BossEvents.BombHeadStage(15), 0, "fresh")
	T.eq(BossEvents.BombHeadStage(8), 0, "at 8")
	T.eq(BossEvents.BombHeadStage(7.9), 1, "under 8")
	T.eq(BossEvents.BombHeadStage(3), 1, "at 3")
	T.eq(BossEvents.BombHeadStage(2.9), 2, "under 3")
	T.eq(BossEvents.BombHeadStage(0), 2, "about to blow")
	T.eq(BossEvents.BOMB_HEAD_TEXT, "Take your big bomb head back to Merasmus!", "TF_HALLOWEEN_MERASMUS_YOU_ARE_BOMB")
end)

T.test("every boss event has a cue with a line; its sound, when it has one, is a name", function()
	for _, name in ipairs(BossEvents.NAMES) do
		local cue = BossEvents.Cue(name, {
			level = 1,
			time_remaining = 10,
			player = {},
		}, function() return "Pyro" end)
		T.eq(type(cue.text), "string", name .. " text")
		T.eq(cue.sound == nil or type(cue.sound) == "string", true, name .. " sound")
	end
	T.eq(type(BossEvents.Cue(BossEvents.PUMPKIN_LORD_SUMMONED, {}).sound), "string", "the Horsemann's music")
end)

T.finish()
