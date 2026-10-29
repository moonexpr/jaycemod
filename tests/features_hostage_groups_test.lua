-- Hostage groups (features.hostage.groups): the hostages standing near one
-- another, the unit the AI war organises its squads by on both teams. Each
-- team forms a squad for every group, and every squad owns one group.
local T = dofile("tests/harness.lua")
local Groups = T.require("features.hostage.groups")
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

-- cs_office's four hostages: two pairs, one at each end of the terrorists' side.
local OFFICE = {
	{ id = "h1", pos = P(1784, 734, -124) },
	{ id = "h2", pos = P(1744, 802, -124) },
	{ id = "h3", pos = P(2048, -344, -156) },
	{ id = "h4", pos = P(1984, -344, -156) },
}

T.test("cs_office's four hostages are two groups of two", function()
	local groups = Groups.Cluster(OFFICE)
	T.eq(#groups, 2, "groups")
	T.eq(table.concat(groups[1].ids, ","), "h1,h2", "the first group")
	T.eq(table.concat(groups[2].ids, ","), "h3,h4", "the second group")
	T.eq(groups[1].index, 1, "index 1")
	T.eq(groups[2].index, 2, "index 2")
end)

T.test("a group's centre is the middle of its hostages", function()
	local g = Groups.Cluster(OFFICE)[1]
	T.near(g.center.x, 1764, 1e-6, "x")
	T.near(g.center.y, 768, 1e-6, "y")
	T.near(g.center.z, -124, 1e-6, "z")
end)

T.test("hostages are linked through their neighbours, not only to one another", function()
	local line = {
		{ id = "a", pos = P(0, 0) },
		{ id = "b", pos = P(Groups.RADIUS - 1, 0) },
		{ id = "c", pos = P(2 * Groups.RADIUS - 2, 0) },
	}
	T.eq(#Groups.Cluster(line), 1, "a chain is one group")
end)

T.test("hostages further apart than the radius are separate groups", function()
	local apart = { { id = "a", pos = P(0, 0) }, { id = "b", pos = P(Groups.RADIUS + 1, 0) } }
	T.eq(#Groups.Cluster(apart), 2, "two groups")
end)

T.test("groups come in the order of their first hostage, whatever order the hostages are listed in", function()
	local shuffled = { OFFICE[3], OFFICE[1], OFFICE[4], OFFICE[2] }
	local groups = Groups.Cluster(shuffled)
	T.eq(table.concat(groups[1].ids, ","), "h1,h2", "h1's group is first")
	T.eq(table.concat(groups[2].ids, ","), "h3,h4", "h3's group second")
end)

T.test("a hostage is found in its group; an unknown one is the caller's mistake", function()
	local groups = Groups.Cluster(OFFICE)
	T.eq(Groups.Of(groups, "h4").index, 2, "h4")
	T.eq(pcall(Groups.Of, groups, "nobody"), false, "nobody")
end)

T.test("no hostages, no groups; a hostage named twice is refused", function()
	T.eq(#Groups.Cluster({}), 0, "none")
	T.eq(pcall(Groups.Cluster, { OFFICE[1], OFFICE[1] }), false, "twice")
end)

-- Squads ------------------------------------------------------------------------

local function Squad(team, role, index)
	return { team = team, role = role, index = index }
end

local JOBS = { courier = true, ctf_defend = true }

local function Counts(fireTeams, team)
	local counts = {}
	for _, ft in ipairs(fireTeams) do
		if ft.team == team and ft.groupIndex then counts[ft.groupIndex] = (counts[ft.groupIndex] or 0) + 1 end
	end
	return counts
end

T.test("each team's squads take the groups in turn, so every group has one", function()
	local groups = Groups.Cluster(OFFICE)
	local squads = {
		Squad(BLUE, "courier", 0), Squad(BLUE, "courier", 1),
		Squad(RED, "ctf_defend", 0), Squad(RED, "ctf_defend", 1),
	}
	Groups.Assign(squads, groups, JOBS)
	for _, team in ipairs({ RED, BLUE }) do
		local counts = Counts(squads, team)
		T.eq(counts[1], 1, "team " .. team .. " group 1")
		T.eq(counts[2], 1, "team " .. team .. " group 2")
	end
	T.eq(squads[1].group, groups[1], "the first squad holds the first group")
	T.eq(squads[2].group, groups[2], "the second the second")
end)

T.test("more squads than groups share them evenly", function()
	local groups = Groups.Cluster(OFFICE)
	local squads = {}
	for i = 0, 4 do squads[#squads + 1] = Squad(RED, "ctf_defend", i) end
	Groups.Assign(squads, groups, JOBS)
	local counts = Counts(squads, RED)
	T.eq(counts[1], 3, "the first group has the odd one")
	T.eq(counts[2], 2, "the second")
end)

T.test("a squad keeps its group while the groups are the same", function()
	local groups = Groups.Cluster(OFFICE)
	local squads = { Squad(BLUE, "courier", 0), Squad(BLUE, "courier", 1) }
	Groups.Assign(squads, groups, JOBS)
	local first = squads[2].groupIndex
	table.remove(squads, 1)
	Groups.Assign(squads, Groups.Cluster(OFFICE), JOBS)
	T.eq(squads[1].groupIndex, first, "kept")
end)

T.test("a squad given a different set of groups is dealt again", function()
	local squads = { Squad(BLUE, "courier", 0) }
	Groups.Assign(squads, Groups.Cluster(OFFICE), JOBS)
	local one = Groups.Cluster({ OFFICE[3], OFFICE[4] })
	Groups.Assign(squads, one, JOBS)
	T.eq(squads[1].group, one[1], "the only group")
end)

T.test("squads of other jobs are left without a group", function()
	local squads = { Squad(BLUE, "medic", 0) }
	squads[1].group, squads[1].groupIndex, squads[1].groupKey = {}, 1, "stale"
	Groups.Assign(squads, Groups.Cluster(OFFICE), JOBS)
	T.eq(squads[1].group, nil, "no group")
	T.eq(squads[1].groupIndex, nil, "no index")
end)

T.test("with no groups every squad is free of one", function()
	local squads = { Squad(RED, "ctf_defend", 0) }
	Groups.Assign(squads, Groups.Cluster(OFFICE), JOBS)
	Groups.Assign(squads, Groups.Cluster({}), JOBS)
	T.eq(squads[1].group, nil, "freed")
end)

T.finish()
