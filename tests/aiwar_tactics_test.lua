-- foundation.aiwar.tactics: a fire team's shared contact, bounding
-- overwatch, flanking and falling back.
local T = dofile("tests/harness.lua")
local Tactics = T.require("foundation.aiwar.tactics")

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end
local function Team(index, places)
	local team = { index = index or 0, members = {} }
	local list = {}
	for place = 0, (places or 4) - 1 do
		local member = { place = place, fireTeam = team }
		team.members[place] = member
		list[#list + 1] = member
	end
	return team, list
end

T.test("what one member sees its team knows, until it is too old", function()
	local team = Team()
	Tactics.Report(team, P(100, 0), 10)
	T.eq(Tactics.Contact(team, 12).pos.x, 100, "known")
	T.eq(Tactics.Contact(team, 10 + Tactics.CONTACT_MEMORY + 1), nil, "forgotten")
end)

T.test("a member's death is its team's contact, there for its squadmates to investigate, longer than a sighting", function()
	local team = Team()
	Tactics.ReportDeath(team, P(300, 50), 10)
	T.eq(Tactics.Contact(team, 10).pos.x, 300, "where to go")
	T.eq(Tactics.INVESTIGATE_MEMORY > Tactics.CONTACT_MEMORY, true, "kept longer than a sighting")
	T.eq(Tactics.Contact(team, 10 + Tactics.CONTACT_MEMORY + 1) ~= nil, true, "still investigated")
	T.eq(Tactics.Contact(team, 10 + Tactics.INVESTIGATE_MEMORY + 1), nil, "given up")
	Tactics.Report(team, P(400, 0), 12)
	T.eq(Tactics.Contact(team, 12).pos.x, 400, "an enemy seen takes its place")
end)

T.test("the elements bound in turn: the movers all arrive, then the others move", function()
	local team, members = Team()
	local bound = Tactics.Bound(team, 0)
	T.eq(bound.moving, 0, "the even places move first")
	T.eq(Tactics.Element(members[2]), 1, "place 1 holds")
	Tactics.Arrived(team, members[1])
	T.eq(Tactics.UpdateBound(team, members, 1), false, "one mover still on its way")
	Tactics.Arrived(team, members[3])
	T.eq(Tactics.UpdateBound(team, members, 1), true, "all arrived: swap")
	T.eq(team.bound.moving, 1, "the odd places move")
end)

T.test("a bound that takes too long swaps anyway", function()
	local team, members = Team()
	Tactics.Bound(team, 0)
	T.eq(Tactics.UpdateBound(team, members, Tactics.BOUND_TIME), true, "timed out")
end)

T.test("odd teams flank, to alternating sides, beside the enemy", function()
	T.eq(Tactics.Flanks({ index = 0 }), false, "the first team goes straight")
	T.eq(Tactics.Flanks({ index = 1 }), true, "the second flanks")
	T.eq(Tactics.FlankSide({ index = 1 }) ~= Tactics.FlankSide({ index = 3 }), true, "the next flanker the other side")
	local point = Tactics.FlankPoint(P(0, 0), P(1000, 0), 1)
	T.near(point.x, 1000, 1e-6, "level with the enemy")
	T.near(math.abs(point.y), Tactics.FLANK_OFFSET, 1e-6, "off to the side")
end)

T.test("a team falls back when down to its last or overrun, a step at a time", function()
	local team = Team()
	T.eq(Tactics.ShouldFallBack(Team(), 1, 1000, 0), false, "a team of one is not down to its last")
	T.eq(Tactics.ShouldFallBack(team, 3, 1000, 0), false, "holding")
	T.eq(Tactics.ShouldFallBack(team, 1, 1000, 0), true, "down to one")
	T.eq(Tactics.ShouldFallBack(team, 3, 100, 0), true, "the enemy on the post")
	Tactics.FallBack(team, 0)
	T.eq(Tactics.ShouldFallBack(team, 1, 100, 1), false, "not again at once")
	local point = Tactics.FallbackPoint(P(0, 0), P(500, 0), 2)
	T.near(point.x, -2 * Tactics.FALLBACK_STEP, 1e-6, "away from the threat")
	Tactics.Regroup(team)
	T.eq(team.fallback, nil, "back to the post")
end)

T.test("toward stops at the target", function()
	local p = Tactics.Toward(P(0, 0), P(100, 0), 300)
	T.eq(p.x, 100, "not past it")
	p = Tactics.Toward(P(0, 0), P(1000, 0), 300)
	T.near(p.x, 300, 1e-6, "the distance along")
end)

T.finish()
