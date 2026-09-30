-- Post-round carnage: foundation.aiwar.hunt (the winners' board of
-- sightings, where they hunt and where the losers hide), and the orders'
-- humiliation phase, driven as scenarios against tests/fake_soldier.lua.
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local Hunt = T.require("foundation.aiwar.hunt")
local Teams = T.require("foundation.teams")

local RED, BLUE = Teams.RED, Teams.BLUE
local P = FS.Point

local function Near(p, q, what)
	T.eq(FS.Distance(p, q) < 1e-6, true, string.format("%s: (%g, %g) vs (%g, %g)", what, p.x, p.y, q.x, q.y))
end

-- The hunt's board -----------------------------------------------------------

T.test("a sighting is kept for HUNT_MEMORY, newest first, one per enemy, for its team only", function()
	local board = Hunt.Board.New()
	board:Report(BLUE, "red1", P(100, 0), 10)
	board:Report(BLUE, "red2", P(200, 0), 12)
	board:Report(BLUE, "red1", P(150, 0), 13)
	local seen = board:Sightings(BLUE, 14)
	T.eq(#seen, 2, "two enemies seen")
	T.eq(seen[1].subject, "red1", "the newest first")
	Near(seen[1].pos, P(150, 0), "where it was last seen")
	T.eq(seen[1].time, 13, "and when")
	T.eq(#board:Sightings(RED, 14), 0, "RED saw nothing")
	T.eq(#board:Sightings(BLUE, 12 + Hunt.HUNT_MEMORY), 2, "at the edge of memory")
	local later = board:Sightings(BLUE, 12 + Hunt.HUNT_MEMORY + 0.5)
	T.eq(#later, 1, "red2 forgotten")
	T.eq(later[1].subject, "red1", "red1 still remembered")
end)

T.test("the quarry is the nearest sighting", function()
	local sightings = {
		{
			subject = "far",
			pos = P(900, 0),
			time = 5,
		},
		{
			subject = "near",
			pos = P(0, 300),
			time = 4,
		},
	}
	T.eq(Hunt.Quarry(sightings, P(0, 0)).subject, "near", "nearest wins")
	T.eq(Hunt.Quarry({}, P(0, 0)), nil, "none seen")
end)

local function Field(spawns)
	return {
		winner = BLUE,
		spawns = spawns,
	}
end

T.test("a hunter goes for its quarry, else for the losers' spawns by slot", function()
	local spawns = {
		[RED] = { P(1000, 0), P(1000, 500), P(1000, 1000) },
		[BLUE] = { P(-1000, 0) },
	}
	local field = Field(spawns)
	local member = {
		team = BLUE,
		slot = 4,
	}
	local sightings = { {
		subject = "red1",
		pos = P(300, 20),
		time = 1,
	} }
	Near(Hunt.HuntGoal(field, member, sightings, P(0, 0)), P(300, 20), "the quarry")
	Near(Hunt.HuntGoal(field, member, {}, P(0, 0)), spawns[RED][4 % 3 + 1], "a losers' spawn, by slot")
	T.eq(Hunt.HuntGoal(Field(nil), member, {}, P(0, 0)), nil, "no spawns known: nowhere")
end)

T.test("a loser hides at its own nearest spawn", function()
	local spawns = {
		[RED] = { P(1000, 0), P(200, 0) },
		[BLUE] = { P(-1000, 0) },
	}
	local member = {
		team = RED,
		slot = 0,
	}
	Near(Hunt.Hideout(Field(spawns), member, P(0, 0)), P(200, 0), "the nearest of its own")
	T.eq(Hunt.Hideout(Field(nil), member, P(0, 0)), nil, "no spawns: no hideout")
	T.eq(Hunt.Hideout(Field({ [BLUE] = spawns[BLUE] }), member, P(0, 0)), nil, "none of its own")
end)

T.finish()
