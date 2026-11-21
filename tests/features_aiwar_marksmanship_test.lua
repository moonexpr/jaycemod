-- features.aiwar.marksmanship: how well the AI war's soldiers shoot, by
-- TF2's bot difficulty (tf_bot_difficulty: 0 easy, 1 normal, 2 hard, 3
-- expert), as their attention, never their guns: how long before the first
-- shot at a new enemy (reaction), how quickly their eyes read where it is
-- going (track: the gains of their vision, the engine's CLuaNextBotVision,
-- whose reading of a turn by its gains is held by the binary's own tests,
-- native/src/nextbot/known.rs) and how their hands pan onto it (pan,
-- nextsoldier.body.player_body's Pan).
local T = dofile ("tests/harness.lua")
local M = T.require ("features.aiwar.marksmanship")
local Body = nextsoldier.body.player_body

local TICK = 0.015

T.test ("four levels, TF2's, normal by default", function ()
	T.eq (M.EASY,    0,        "easy")
	T.eq (M.NORMAL,  1,        "normal")
	T.eq (M.HARD,    2,        "hard")
	T.eq (M.EXPERT,  3,        "expert")
	T.eq (M.DEFAULT, M.NORMAL, "normal by default")
end)

T.test ("an unknown level is clamped to the nearest", function ()
	T.eq (M.For (-4),  M.For (M.EASY),   "below easy")
	T.eq (M.For (9),   M.For (M.EXPERT), "above expert")
	T.eq (M.For (1.6), M.For (M.HARD),   "rounded")
end)

-- Whether a level's eyes read at least as quickly as another's on every gain,
-- and more quickly on one: the binary's filter, so read, is less off after a
-- turn.
local function Quicker (track, than)
	local some = false
	for _, gain in ipairs ({ "alpha", "beta", "gamma" }) do
		if track [gain] < than [gain] then return false end
		some = some or track [gain] > than [gain]
	end
	return some
end

-- How long a level's hand takes to pan 40 degrees onto a still enemy, to
-- within a degree and staying there.
local function Acquire (level)
	local hand, pitch, yaw, settledAt = Body.Hand (), 0, 0, nil
	for i = 1, math.floor (3 / TICK) do
		pitch, yaw = Body.Pan (hand, pitch, yaw, 0, 40, 0, 0, TICK, M.For (level).pan)
		if math.abs (yaw - 40) > 1 then settledAt = nil elseif not settledAt then settledAt = i * TICK end
	end
	return settledAt
end

T.test ("every level's hand comes onto a still enemy, its eyes reading its moves", function ()
	for level = M.EASY, M.EXPERT do
		local track = M.For (level).track
		T.eq (Acquire (level) ~= nil,             true, level .. ": its hand comes onto a still enemy")
		T.eq (track.alpha > 0 and track.beta > 0, true, level .. ": its eyes read where and how fast")
		T.eq (M.For (level).reaction >= 0,        true, level .. ": a reaction its vision takes")
	end
end)

T.test ("each level up reacts sooner, reads a change of course sooner and pans onto an enemy sooner", function ()
	for level = M.EASY, M.HARD do
		local this, harder = M.For (level), M.For (level + 1)
		T.eq (this.reaction > harder.reaction,       true, level .. ": slower to react")
		T.eq (Quicker (harder.track, this.track),    true, level .. ": slower to read a change of course")
		T.eq (Acquire (level) > Acquire (level + 1), true, level .. ": later onto an enemy")
	end
end)

T.test ("no level's hand is perfect: each overshoots or trails a little", function ()
	for level = M.EASY, M.EXPERT do
		local pan = M.For (level).pan
		T.eq (pan.damping < 1 or pan.pursuit < 1, true, level .. ": human")
	end
end)

T.finish ()
