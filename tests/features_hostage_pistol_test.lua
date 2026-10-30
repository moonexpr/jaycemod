-- features.hostage.pistol: the round's one pistol among the hostages. One
-- hostage, drawn at random, is armed as the round begins; when it dies the
-- pistol lies where it fell and every hostage still held or following rushes
-- for it, the first within PICKUP_RANGE taking it up.
local T = dofile("tests/harness.lua")
local Pistol = T.require("features.hostage.pistol")
local Rescue = T.require("features.hostage.model")

T.defined(Pistol.PICKUP_RANGE, "PICKUP_RANGE")
T.defined(Pistol.RELOAD, "RELOAD")

local function P(x, y) return { x = x, y = y, z = 0 } end

T.test("its reload is slower than a soldier's pistol", function()
	local soldiers = nextsoldier.weapons.STATS.weapon_pistol
	T.eq(Pistol.STATS.reload, Pistol.RELOAD, "its own reload")
	T.eq(Pistol.STATS.reload > soldiers.reload, true, "slower")
	T.eq(Pistol.STATS.damage, soldiers.damage, "otherwise the soldiers' pistol")
	T.eq(Pistol.CLASS, "weapon_pistol", "HL2's pistol, as the soldiers carry")
end)

T.test("one hostage is armed, drawn by the random source given", function()
	local ids = { "h1", "h2", "h3" }
	T.eq(Pistol.Arm(ids, function(low, high) return low end):Holder(), "h1", "the first drawn")
	T.eq(Pistol.Arm(ids, function(low, high) return high end):Holder(), "h3", "the last drawn")
	local asked
	Pistol.Arm(ids, function(low, high) asked = { low, high } return low end)
	T.eq(asked[1] == 1 and asked[2] == 3, true, "among all of them")
end)

T.test("no hostages, no pistol", function()
	T.eq(Pistol.Arm({}, function() error("not asked") end), nil, "none")
end)

T.test("dropped, it lies where it fell and no one holds it", function()
	local pistol = Pistol.Arm({ "h1" }, function(low) return low end):Drop(P(10, 20))
	T.eq(pistol:Holder(), nil, "held by no one")
	T.eq(pistol:Lying().x, 10, "where it fell")
end)

T.test("a pistol is dropped only while held, and taken up only while lying", function()
	local held = Pistol.Arm({ "h1" }, function(low) return low end)
	local ok = pcall(function() held:PickUp("h1") end)
	T.eq(ok, false, "held: none takes it up")
	local lying = held:Drop(P(0, 0))
	ok = pcall(function() lying:Drop(P(1, 1)) end)
	T.eq(ok, false, "lying: none drops it")
	T.eq(lying:PickUp("h2"):Holder(), "h2", "taken up")
	T.eq(lying:PickUp("h2"):Lying(), nil, "no longer lying")
end)

T.test("every hostage held or following rushes for a pistol lying, none for one held", function()
	local round = Rescue.New({ "h1", "h2", "h3", "h4" })
	round = round:Follow("h2", "leader"):Follow("h3", "leader"):Rescue("h3"):Kill("h1")
	local lying = Pistol.Arm({ "h1" }, function(low) return low end):Drop(P(0, 0))
	local rushers = lying:Rushers(round)
	table.sort(rushers)
	T.eq(table.concat(rushers, ","), "h2,h4", "the following and the held, not the rescued nor the dead")
	local held = Pistol.Arm({ "h2" }, function(low) return low end)
	T.eq(#held:Rushers(round), 0, "held: none rushes")
end)

T.test("the nearest rusher within PICKUP_RANGE takes it up; none farther", function()
	local lying = Pistol.Arm({ "h1" }, function(low) return low end):Drop(P(0, 0))
	local near, nearer = Pistol.PICKUP_RANGE - 1, Pistol.PICKUP_RANGE / 2
	T.eq(lying:Claimant({ h2 = P(near, 0), h3 = P(0, nearer) }), "h3", "the nearer")
	T.eq(lying:Claimant({ h2 = P(Pistol.PICKUP_RANGE + 1, 0) }), nil, "too far")
	T.eq(Pistol.Arm({ "h1" }, function(low) return low end):Claimant({ h2 = P(0, 0) }), nil, "held: no one claims it")
end)

T.finish()
