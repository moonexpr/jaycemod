-- The Halloween bosses' game events (TF2's modevents.res) and what a client
-- makes of each (ClientModeTFNormal::FireGameEvent, clientmode_tf.cpp): the
-- sound the local player hears and the line it reads, in tf_english.txt's
-- words. The boss models fire them through their port's FireGameEvent
-- (foundation.npc.halloween_boss); the npc feature defines them
-- (features/npc/sh.lua) and its view plays the cues. Small on purpose: a
-- client loads it without the boss models.
local format = string.format
local ipairs = ipairs
module(...)

-- CHeadlessHatmanEmerge::OnStart, CHeadlessHatmanDying::Update: no fields.
PUMPKIN_LORD_SUMMONED = "game_pumpkin_lord_summoned"
PUMPKIN_LORD_KILLED = "game_pumpkin_lord_killed"
-- CEyeballBossEmerge, CEyeballBossDead, CEyeballBossIdle, CEyeballBossEscape,
-- for a map's eyeball only (not a spell's): { level }, and the warning's
-- { time_remaining } in seconds.
EYEBALL_BOSS_SUMMONED = "game_eyeball_boss_summoned"
EYEBALL_BOSS_KILLED = "game_eyeball_boss_killed"
EYEBALL_BOSS_ESCAPE_IMMINENT = "game_eyeball_boss_escape_imminent"
EYEBALL_BOSS_ESCAPED = "game_eyeball_boss_escaped"
-- CMerasmus::Spawn, CMerasmusDying, CMerasmus::LeaveWarning, CMerasmusEscape:
-- { level }, and the warning's { time_remaining }.
MERASMUS_SUMMONED = "game_merasmus_summoned"
MERASMUS_KILLED = "game_merasmus_killed"
MERASMUS_ESCAPE_WARNING = "game_merasmus_escape_warning"
MERASMUS_ESCAPED = "game_merasmus_escaped"
-- Sandcastle's own, for the chat line TF2 sends for each of his killers
-- (the players who hit him in his last 5 s; CMerasmusBehavior::Update's
-- SayText2 of TF_Halloween_Merasmus_Killers): { player, level }.
MERASMUS_KILLER = "game_merasmus_killer"

NAMES = {
	PUMPKIN_LORD_SUMMONED,
	PUMPKIN_LORD_KILLED,
	EYEBALL_BOSS_SUMMONED,
	EYEBALL_BOSS_KILLED,
	EYEBALL_BOSS_ESCAPE_IMMINENT,
	EYEBALL_BOSS_ESCAPED,
	MERASMUS_SUMMONED,
	MERASMUS_KILLED,
	MERASMUS_ESCAPE_WARNING,
	MERASMUS_ESCAPED,
	MERASMUS_KILLER,
}

-- Merasmus's bomb heads (TF_COND_HALLOWEEN_BOMB_HEAD), which TF2 networks
-- as a player condition: { player, duration } when a player gets one,
-- duration 0 when it is gone. Every client hangs the bomb on the player's
-- head (C_TFPlayer::HalloweenBombHeadUpdate); the bomb head's own client
-- reads its orders (ClientPrint, TF_HALLOWEEN_MERASMUS_YOU_ARE_BOMB) and
-- hears the book spin (CreateBombonomiconHint).
HALLOWEEN_BOMB_HEAD = "game_halloween_bomb_head"
BOMB_HEAD_TEXT = "Take your big bomb head back to Merasmus!"
BOMB_HEAD_SOUND = "Halloween.BombinomiconSpin"
BOMB_HAT_MODEL = "models/props_lakeside_event/bomb_temp_hat.mdl"

FIRST_LEVEL = 1 -- CEyeballBoss::m_level starts here; past it the text names the level
IMMINENT_SECONDS = 10 -- at or under this, the escape is imminent rather than soon
-- colorEyeballBossText
EYEBALL_COLOR = {
	r = 134,
	g = 80,
	b = 172,
}

-- An eyeball line: its plain text, or with "(LEVEL n)" past the first level.
-- colorMerasmusText
MERASMUS_COLOR = {
	r = 112,
	g = 176,
	b = 74,
}

-- s_vecBombStages: the hat's skin from 8 s left, then from 3 s left.
local BOMB_STAGES = {
	{
		from = 8,
		stage = 0,
	},
	{
		from = 3,
		stage = 1,
	},
	{
		from = 0,
		stage = 2,
	},
}

-- The bomb's stage (its hat's skin) with this many seconds left.
function BombHeadStage(remaining)
	for _, step in ipairs(BOMB_STAGES) do
		if remaining >= step.from then return step.stage end
	end
	return BOMB_STAGES[#BOMB_STAGES].stage
end

-- A boss's line: its plain text, or with "(LEVEL n)" past the first level.
local function Levelled(fields, plain, levelled)
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
			text = Levelled(fields, "Beware! MONOCULUS! is lurking about...", "Beware! MONOCULUS! (LEVEL %d) is lurking about..."),
			color = EYEBALL_COLOR,
		}
	end,
	[EYEBALL_BOSS_KILLED] = function(fields)
		return {
			sound = "Halloween.MonoculusBossDeath",
			text = Levelled(fields, "MONOCULUS! has been defeated!", "MONOCULUS! (LEVEL %d) has been defeated!"),
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
			text = Levelled(fields, plain, levelled),
			color = EYEBALL_COLOR,
		}
	end,
	[EYEBALL_BOSS_ESCAPED] = function(fields)
		return {
			sound = "Halloween.EyeballBossEscaped",
			text = Levelled(fields, "MONOCULUS! has left to haunt another realm!", "MONOCULUS! (LEVEL %d) has left to haunt another realm!"),
			color = EYEBALL_COLOR,
		}
	end,
	[MERASMUS_SUMMONED] = function(fields)
		return {
			sound = "Halloween.MerasmusBossSpawn",
			text = Levelled(fields, "MERASMUS! has appeared!", "MERASMUS! (LEVEL %d) has appeared!"),
			color = MERASMUS_COLOR,
		}
	end,
	-- No sound: CMerasmusDying broadcast his death's music as he fell.
	[MERASMUS_KILLED] = function(fields)
		return {
			text = Levelled(fields, "MERASMUS! has been defeated!", "MERASMUS! (LEVEL %d) has been defeated!"),
			color = MERASMUS_COLOR,
		}
	end,
	[MERASMUS_ESCAPE_WARNING] = function(fields)
		local seconds = fields.time_remaining
		local imminent = seconds <= IMMINENT_SECONDS
		-- TF_Halloween_Merasmus_Escaping_In_60, _30 and _10
		local plain = format("MERASMUS! is leaving in %d seconds%s", seconds, imminent and "!" or "...")
		local levelled = format("MERASMUS! (LEVEL %%d) is leaving in %d seconds%s", seconds, imminent and "!" or "...")
		return {
			sound = imminent and "Halloween.EyeballBossEscapeImminent" or "Halloween.EyeballBossEscapeSoon",
			text = Levelled(fields, plain, levelled),
			color = MERASMUS_COLOR,
		}
	end,
	[MERASMUS_ESCAPED] = function(fields)
		return {
			sound = "Halloween.EyeballBossEscaped",
			text = Levelled(fields, "MERASMUS! has gone home!", "MERASMUS! (LEVEL %d) has gone home!"),
			color = MERASMUS_COLOR,
		}
	end,
	-- TF_Halloween_Merasmus_Killers, and _LevelUp_Killers past the first level
	[MERASMUS_KILLER] = function(fields, nameOf)
		-- the name is joined on, never formatted, so a % in it is just a %
		return { text = nameOf(fields.player) .. Levelled(fields, " has defeated MERASMUS!", " has defeated MERASMUS! (LEVEL %d)") }
	end,
}

-- { sound (nil: none), text, color (nil: the chat's own) } for the event's
-- fields; nameOf(player) gives a player's name, for the events that name
-- one.
function Cue(name, fields, nameOf)
	return CUES[name](fields, nameOf)
end
