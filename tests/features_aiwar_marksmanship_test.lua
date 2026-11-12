-- features.aiwar.marksmanship: how well the AI war's soldiers shoot, by
-- TF2's bot difficulty (tf_bot_difficulty: 0 easy, 1 normal, 2 hard, 3
-- expert), as their attention, never their guns: how long before the first
-- shot at a new enemy (reaction), how quickly their eyes read where it is
-- going (track, nextsoldier.senses.vision) and how their hands pan onto it
-- (pan, nextsoldier.body.player_body's Pan).
local T = dofile ("tests/harness.lua")
local M = T.require ("features.aiwar.marksmanship")
local Vision = nextsoldier.senses.vision
local Body = nextsoldier.body.player_body

local LOOK, TICK = 0.2, 0.015

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

-- How far off a level's eyes read an enemy that turns back at speed, summed
-- over the two seconds after it turned (units by seconds), and how far off
-- its speed once it has run on steadily.
local function Read (level)
	local v = Vision.New ({ reaction = 0, memory = 30, track = M.For (level).track })
	local function Path (t) return t < 3 and 250 * t or 250 * (6 - t) end
	local function Look (t) v:Update (t, { enemy = { x = Path (t), y = 0, z = 0 } }, function () return false end) end
	local t, turned = 0, 0
	while t < 5 do
		Look (t)
		if t > 3 then turned = turned + math.abs (v:Estimate ("enemy", t).x - Path (t)) * LOOK end
		t = t + LOOK
	end
	while t < 12 do Look (t) t = t + LOOK end
	local _, velocity = v:Estimate ("enemy", t)
	return turned, math.abs (velocity.x + 250)
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

T.test ("every level's eyes settle on a steady enemy, and its hand on a still one", function ()
	for level = M.EASY, M.EXPERT do
		local _, steady = Read (level)
		T.eq (steady < 1,             true, level .. ": reads a steady enemy's speed, off by " .. steady)
		T.eq (Acquire (level) ~= nil, true, level .. ": its hand comes onto a still enemy")
	end
end)

T.test ("each level up reacts sooner, reads a change of course sooner and pans onto an enemy sooner", function ()
	for level = M.EASY, M.HARD do
		local this, harder = M.For (level), M.For (level + 1)
		T.eq (this.reaction > harder.reaction,       true, level .. ": slower to react")
		T.eq (Read (level) > Read (level + 1),       true, level .. ": further off after a turn")
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
