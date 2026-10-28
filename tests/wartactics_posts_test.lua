-- wartactics.posts: where defenders establish their line: posts near
-- the checkpoint the attackers are heading for, that see it, ranked by
-- range, elevation and cover, and spaced apart.
local T = dofile("tests/harness.lua")
local Posts = wartactics.posts

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

-- A candidate `range` units from the checkpoint and far from the cart.
local function Candidate(t)
	return {
		pos = t.pos or P(t.range or Posts.IDEAL_RANGE, 0, t.elevation or 0),
		sees = t.sees ~= false,
		toObjective = t.range or Posts.IDEAL_RANGE,
		toCart = t.toCart or 2000,
		elevation = t.elevation or 0,
		cover = t.cover or false,
		sniper = t.sniper or 0,
	}
end

T.test("a post that cannot see the checkpoint, or is too far from it or too near the cart, is no post", function()
	T.eq(Posts.Score(Candidate({ sees = false })), nil, "blind")
	T.eq(Posts.Score(Candidate({ range = Posts.MAX_RANGE + 1 })), nil, "too far")
	T.eq(Posts.Score(Candidate({ toCart = Posts.MIN_CART_DISTANCE - 1 })), nil, "where the attackers are")
	T.eq(Posts.Score(Candidate({})) ~= nil, true, "a good one")
end)

T.test("a post at the ideal range beats one nearer or farther", function()
	local ideal = Posts.Score(Candidate({}))
	T.eq(ideal > Posts.Score(Candidate({ range = 200 })), true, "nearer")
	T.eq(ideal > Posts.Score(Candidate({ range = 1300 })), true, "farther")
end)

T.test("high ground beats low ground, and both beat level ground", function()
	local level = Posts.Score(Candidate({}))
	local high = Posts.Score(Candidate({ elevation = 200 }))
	local low = Posts.Score(Candidate({ elevation = -200 }))
	T.eq(high > low, true, "high over low: above the point")
	T.eq(low > level, true, "low over level: down in a pit")
	T.eq(Posts.Score(Candidate({ elevation = 5000 })), Posts.Score(Candidate({ elevation = Posts.ELEVATION_CAP })), "height counts up to a cap")
end)

T.test("cover and the nav mesh's sniper spots add to a post", function()
	local plain = Posts.Score(Candidate({}))
	T.eq(Posts.Score(Candidate({ cover = true })) > plain, true, "cover")
	local good = Posts.Score(Candidate({ sniper = Posts.GOOD_SNIPER }))
	T.eq(good > plain, true, "good sniper spot")
	T.eq(Posts.Score(Candidate({ sniper = Posts.IDEAL_SNIPER })) > good, true, "ideal sniper spot")
end)

T.test("posts are picked best first, spaced apart, as many as asked", function()
	local picked = Posts.Pick({
		Candidate({ pos = P(0, 300), elevation = 0 }),
		Candidate({ pos = P(10, 0), elevation = 300 }), -- best, but crowds the next
		Candidate({ pos = P(20, 0), elevation = 200 }),
		Candidate({ pos = P(500, 0), elevation = 100 }),
		Candidate({ pos = P(900, 0), sees = false }),
	}, 3)
	T.eq(#picked, 3, "three")
	T.eq(picked[1].x, 10, "the best")
	T.eq(picked[2].x, 500, "the next best far enough from it")
	T.eq(picked[3].x, 0, "then the rest, still spaced")
end)

-- Attackers: the line pushed forward.

local function Forward(t)
	return {
		pos = t.pos or P(0, 0, t.elevation or 0),
		sees = t.sees ~= false,
		ahead = t.ahead or 400,
		toCart = t.toCart or 400,
		elevation = t.elevation or 0,
		cover = t.cover or false,
		sniper = t.sniper or 0,
	}
end

T.test("an attackers' post must be ahead of the cart, near it, and in sight of it", function()
	T.eq(Posts.ScoreForward(Forward({ ahead = -10 })), nil, "behind the cart")
	T.eq(Posts.ScoreForward(Forward({ ahead = Posts.MAX_LEAD + 1 })), nil, "too far ahead")
	T.eq(Posts.ScoreForward(Forward({ toCart = Posts.MAX_COVER_RANGE + 1 })), nil, "too far from the cart")
	T.eq(Posts.ScoreForward(Forward({ sees = false })), nil, "cannot cover the cart")
	T.eq(Posts.ScoreForward(Forward({})) ~= nil, true, "a good one")
end)

T.test("the farther ahead the better: attackers push the line forward", function()
	T.eq(Posts.ScoreForward(Forward({ ahead = 800 })) > Posts.ScoreForward(Forward({ ahead = 300 })), true, "forward")
	T.eq(Posts.ScoreForward(Forward({ ahead = 800 })) > Posts.ScoreForward(Forward({ ahead = 300, elevation = 256, cover = true })), true, "forward counts most")
	T.eq(Posts.ScoreForward(Forward({ elevation = 200 })) > Posts.ScoreForward(Forward({})), true, "high ground still helps")
end)

T.test("attackers' posts are picked the same way, best first and spaced", function()
	local picked = Posts.Pick({
		Forward({ pos = P(0, 0), ahead = 800 }),
		Forward({ pos = P(10, 0), ahead = 790 }),
		Forward({ pos = P(400, 0), ahead = 500 }),
	}, 3, Posts.ScoreForward)
	T.eq(#picked, 2, "two apart")
	T.eq(picked[1].x .. "," .. picked[2].x, "0,400", "front first")
end)

-- Guards: posts round a control point its team holds (TF2's
-- CSelectDefenseAreaForPoint).

local function Guard(t)
	return {
		pos = t.pos or P(0, 0, t.elevation or 0),
		sees = t.sees ~= false,
		toPoint = t.toPoint or Posts.IDEAL_RANGE,
		elevation = t.elevation or 0,
		cover = t.cover or false,
		sniper = t.sniper or 0,
		past = t.past or 0,
		anywhere = t.anywhere == true,
	}
end

T.test("a guard post must see the point, within MAX_GUARD_RANGE, not far past it, and not far below it", function()
	T.eq(Posts.ScoreGuard(Guard({ sees = false })), nil, "unseen")
	T.eq(Posts.ScoreGuard(Guard({ toPoint = Posts.MAX_GUARD_RANGE + 1 })), nil, "too far")
	T.eq(Posts.ScoreGuard(Guard({ toPoint = Posts.MAX_GUARD_RANGE })) ~= nil, true, "at the range")
	T.eq(Posts.ScoreGuard(Guard({ past = Posts.PAST_POINT_LIMIT + 1 })), nil, "too far past the point, toward the enemy")
	T.eq(Posts.ScoreGuard(Guard({ past = Posts.PAST_POINT_LIMIT })) ~= nil, true, "at the limit")
	T.eq(Posts.ScoreGuard(Guard({ past = Posts.PAST_POINT_LIMIT + 1, anywhere = true })) ~= nil, true, "anywhere: King of the Hill")
	T.eq(Posts.ScoreGuard(Guard({ elevation = -Posts.GUARD_TOO_LOW - 1 })), nil, "too far below")
	T.eq(Posts.ScoreGuard(Guard({ elevation = -Posts.GUARD_TOO_LOW })) ~= nil, true, "at the depth limit")
	T.eq(Posts.ScoreGuard(Guard({})) ~= nil, true, "a good one")
end)

T.test("the higher guard post with cover wins", function()
	local plain = Posts.ScoreGuard(Guard({}))
	local high = Posts.ScoreGuard(Guard({ elevation = 150 }))
	local highCover = Posts.ScoreGuard(Guard({ elevation = 150, cover = true }))
	T.eq(high > plain, true, "high ground")
	T.eq(highCover > high, true, "with cover")
	local picked = Posts.Pick({
		Guard({ pos = P(0, 0) }),
		Guard({ pos = P(400, 0, 150), elevation = 150, cover = true }),
		Guard({ pos = P(800, 0, 150), elevation = 150 }),
	}, 1, Posts.ScoreGuard)
	T.eq(picked[1].x, 400, "the high covered spot")
end)

T.finish()
