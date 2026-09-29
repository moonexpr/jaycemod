-- Where soldiers establish their line (the EstablishLine objective), among
-- the nav mesh's hiding spots and high or low ground.
-- Defenders (Score): posts near the checkpoint the attackers are heading
-- for, that see it. A candidate is { pos, sees (a clear line to the
-- checkpoint from eye height), toObjective, toCart (distances), elevation
-- (above the checkpoint), cover (an in-cover hiding spot), sniper (0,
-- GOOD_SNIPER or IDEAL_SNIPER, from the nav mesh's hiding spot flags) }.
-- Attackers (ScoreForward): posts ahead of their own cart, near it and in
-- sight of it, the farther forward the better, so the line is pushed
-- ahead of the cart. A candidate has ahead (how far ahead of the cart
-- along the track) and sees (a clear line to the cart) instead.
local abs, ipairs, min, sort, sqrt = math.abs, ipairs, math.min, table.sort, math.sqrt
module(...)

MAX_RANGE = 1400 -- from the checkpoint
IDEAL_RANGE = 500
MIN_CART_DISTANCE = 500 -- nearer the attackers' cart is where they already are
ELEVATION_CAP = 256
SPACING = 128 -- between two posts

GOOD_SNIPER, IDEAL_SNIPER = 1, 2

MAX_LEAD = 900 -- how far ahead of their cart attackers may post
MAX_COVER_RANGE = 1000 -- how far from their cart

local W_RANGE, W_HIGH, W_LOW, W_COVER = 1, 1.5, 1, 0.5
local W_AHEAD = 4 -- pushing forward outweighs height and cover together
local W_SNIPER = { [0] = 0, [GOOD_SNIPER] = 0.75, [IDEAL_SNIPER] = 1.25 }

-- Height, cover and the sniper flags, which both sides value.
local function Ground(c)
	local height = min(abs(c.elevation), ELEVATION_CAP) / ELEVATION_CAP
	local score = height * (c.elevation >= 0 and W_HIGH or W_LOW)
	if c.cover then score = score + W_COVER end
	return score + W_SNIPER[c.sniper]
end

-- A defenders' post's worth, or nil for no post at all.
function Score(c)
	if not c.sees or c.toObjective > MAX_RANGE or c.toCart < MIN_CART_DISTANCE then return nil end
	return -W_RANGE * abs(c.toObjective - IDEAL_RANGE) / IDEAL_RANGE + Ground(c)
end

-- An attackers' post's worth, or nil for no post at all.
function ScoreForward(c)
	if not c.sees or c.ahead <= 0 or c.ahead > MAX_LEAD or c.toCart > MAX_COVER_RANGE then return nil end
	return W_AHEAD * c.ahead / MAX_LEAD + Ground(c)
end

local function Apart(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return sqrt(dx * dx + dy * dy + dz * dz) >= SPACING
end

-- Up to `count` posts, best first by `scorer` (default Score), each at
-- least SPACING from those picked before it.
function Pick(candidates, count, scorer)
	scorer = scorer or Score
	local ranked = {}
	for _, c in ipairs(candidates) do
		local score = scorer(c)
		if score then ranked[#ranked + 1] = { pos = c.pos, score = score } end
	end
	sort(ranked, function(a, b) return a.score > b.score end)
	local picked = {}
	for _, r in ipairs(ranked) do
		if #picked >= count then break end
		local free = true
		for _, p in ipairs(picked) do
			if not Apart(r.pos, p) then free = false break end
		end
		if free then picked[#picked + 1] = r.pos end
	end
	return picked
end
