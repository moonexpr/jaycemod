-- The Halloween bosses' game events (TF2's modevents.res) and what a client
-- makes of each (ClientModeTFNormal::FireGameEvent, clientmode_tf.cpp): the
-- sound the local player hears and the line it reads, in tf_english.txt's
-- words. The boss models fire them through their port's FireGameEvent
-- (foundation.npc.halloween_boss); the npc feature defines them
-- (features/npc/sh.lua) and its view plays the cues. Small on purpose: a
-- client loads it without the boss models.
local format = string.format
module(...)

-- CHeadlessHatmanEmerge::OnStart, CHeadlessHatmanDying::Update: no fields.
PUMPKIN_LORD_SUMMONED = "pumpkin_lord_summoned"
PUMPKIN_LORD_KILLED = "pumpkin_lord_killed"
-- CEyeballBossEmerge, CEyeballBossDead, CEyeballBossIdle, CEyeballBossEscape,
-- for a map's eyeball only (not a spell's): { level }, and the warning's
-- { time_remaining } in seconds.
EYEBALL_BOSS_SUMMONED = "eyeball_boss_summoned"
EYEBALL_BOSS_KILLED = "eyeball_boss_killed"
EYEBALL_BOSS_ESCAPE_IMMINENT = "eyeball_boss_escape_imminent"
EYEBALL_BOSS_ESCAPED = "eyeball_boss_escaped"

NAMES = {
	PUMPKIN_LORD_SUMMONED,
	PUMPKIN_LORD_KILLED,
	EYEBALL_BOSS_SUMMONED,
	EYEBALL_BOSS_KILLED,
	EYEBALL_BOSS_ESCAPE_IMMINENT,
	EYEBALL_BOSS_ESCAPED,
}

FIRST_LEVEL = 1 -- CEyeballBoss::m_level starts here; past it the text names the level
IMMINENT_SECONDS = 10 -- at or under this, the escape is imminent rather than soon
-- colorEyeballBossText
EYEBALL_COLOR = {
	r = 134,
	g = 80,
	b = 172,
}

-- An eyeball line: its plain text, or with "(LEVEL n)" past the first level.
local function Eyeball(fields, plain, levelled)
	if fields.level > FIRST_LEVEL then return format(levelled, fields.level) end
	return plain
end

local CUES = {
	[PUMPKIN_LORD_SUMMONED] = function()
		return {
			sound = "Halloween.HeadlessBossSpawn",
			text = "The Horseless Headless Horsemann has appeared!",
		}
	end,
	[PUMPKIN_LORD_KILLED] = function()
		return {
			sound = "Halloween.HeadlessBossDeath",
			text = "The Horseless Headless Horsemann has been defeated!",
		}
	end,
	[EYEBALL_BOSS_SUMMONED] = function(fields)
		return {
			sound = "Halloween.MonoculusBossSpawn",
			text = Eyeball(fields, "Beware! MONOCULUS! is lurking about...", "Beware! MONOCULUS! (LEVEL %d) is lurking about..."),
			color = EYEBALL_COLOR,
		}
	end,
	[EYEBALL_BOSS_KILLED] = function(fields)
		return {
			sound = "Halloween.MonoculusBossDeath",
			text = Eyeball(fields, "MONOCULUS! has been defeated!", "MONOCULUS! (LEVEL %d) has been defeated!"),
			color = EYEBALL_COLOR,
		}
	end,
	[EYEBALL_BOSS_ESCAPE_IMMINENT] = function(fields)
		local seconds = fields.time_remaining
		local imminent = seconds <= IMMINENT_SECONDS
		-- TF_Halloween_Eyeball_Boss_Escaping_In_60, _30 and _10
		local plain = format("MONOCULUS! is leaving in %d seconds%s", seconds, imminent and "!" or "...")
		local levelled = format("MONOCULUS! (LEVEL %%d) is leaving in %d seconds%s", seconds, imminent and "!" or "...")
		return {
			sound = imminent and "Halloween.EyeballBossEscapeImminent" or "Halloween.EyeballBossEscapeSoon",
			text = Eyeball(fields, plain, levelled),
			color = EYEBALL_COLOR,
		}
	end,
	[EYEBALL_BOSS_ESCAPED] = function(fields)
		return {
			sound = "Halloween.EyeballBossEscaped",
			text = Eyeball(fields, "MONOCULUS! has left to haunt another realm!", "MONOCULUS! (LEVEL %d) has left to haunt another realm!"),
			color = EYEBALL_COLOR,
		}
	end,
}

-- { sound, text, color (nil: the chat's own) } for the event's fields.
function Cue(name, fields)
	return CUES[name](fields)
end
