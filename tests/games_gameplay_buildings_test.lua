-- games.gameplay.buildings: the rules of what a support unit builds, as values: a sentry, a
-- teleporter and an access door, each put up over its construction time, harmed only by enemies.
local T = dofile("tests/harness.lua")
local Buildings = gameplay.buildings
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE

T.test("each kind of building has its health and its construction time", function()
	for _, kind in ipairs({ Buildings.SENTRY, Buildings.TELEPORTER, Buildings.DISPENSER, Buildings.DOOR }) do
		T.eq(Buildings.HEALTH[kind] > 0, true, "health: " .. kind)
		T.eq(Buildings.BUILD_TIME[kind] > 0, true, "construction: " .. kind)
	end
end)

T.test("a building goes up over its construction time, from nothing to whole", function()
	local time = Buildings.BUILD_TIME[Buildings.SENTRY]
	T.eq(Buildings.Constructed(Buildings.SENTRY, 10, 10), 0, "begun")
	T.near(Buildings.Constructed(Buildings.SENTRY, 10, 10 + time / 2), 0.5, 1e-9, "half up")
	T.eq(Buildings.Constructed(Buildings.SENTRY, 10, 10 + time * 2), 1, "whole, and no more")
end)

T.test("an unknown kind of building is our bug, refused naming it", function()
	local ok, err = pcall(Buildings.Constructed, "dispenserr", 0, 1)
	T.eq(not ok and tostring(err):find("dispenserr", 1, true) ~= nil, true, "refused")
end)

T.test("a building is harmed by its enemies and the world, never by its own team", function()
	T.eq(Buildings.Harms(RED, BLUE), true, "an enemy")
	T.eq(Buildings.Harms(RED, RED), false, "a teammate")
	T.eq(Buildings.Harms(RED, Teams.UNASSIGNED), true, "the world")
	-- GMod's TEAM_UNASSIGNED, every player's in Sandbox: nobody's teammate.
	T.eq(Buildings.Harms(1001, 1001), true, "anyone, without a playing team")
	T.eq(Buildings.Harms(Teams.UNASSIGNED, Teams.UNASSIGNED), true, "the world, without a team")
end)

T.test("a wrench tends its own team's buildings, never another's", function()
	T.eq(Buildings.Tends(RED, RED), true, "a teammate's")
	T.eq(Buildings.Tends(RED, BLUE), false, "the enemy's")
	T.eq(Buildings.Tends(1001, 1001), true, "anyone's own, without a playing team")
end)

T.test("a wrench's hit mends a built building, never past its health", function()
	local max = Buildings.HEALTH[Buildings.SENTRY]
	T.eq(Buildings.Repaired(1, max), 1 + Buildings.WRENCH_REPAIR, "mended")
	T.eq(Buildings.Repaired(max - 1, max), max, "whole, and no more")
	T.eq(Buildings.Repaired(max, max), max, "already whole")
end)

T.test("a wrench's hit puts a building going up nearer to whole, never past it", function()
	local time, hurry = Buildings.BUILD_TIME[Buildings.SENTRY], Buildings.WRENCH_HURRY
	T.eq(Buildings.Hurried(Buildings.SENTRY, 10, 10), 10 - hurry, "begun earlier")
	T.eq(Buildings.Constructed(Buildings.SENTRY, Buildings.Hurried(Buildings.SENTRY, 10, 10), 10) > 0, true, "nearer")
	T.eq(Buildings.Hurried(Buildings.SENTRY, 10, 10 + time - hurry / 2), 10 + time - hurry / 2 - time, "just whole")
end)

T.test("a building needs tending going up or hurt; the furthest from whole is tended first", function()
	local whole = { constructed = 1, health = 150, max = 150 }
	local hurt = { constructed = 1, health = 100, max = 150 }
	local worse = { constructed = 1, health = 30, max = 150 }
	local rising = { constructed = 0.5, health = 150, max = 150 }
	T.eq(Buildings.Upkeep({ whole }), nil, "none")
	T.eq(Buildings.Upkeep({}), nil, "nothing built")
	T.eq(Buildings.Upkeep({ whole, hurt }), hurt, "the hurt one")
	T.eq(Buildings.Upkeep({ hurt, worse, whole }), worse, "the worse")
	T.eq(Buildings.Upkeep({ hurt, rising }), rising, "going up, half there")
end)

-- Candidates about a sentry at the origin, each a position and a team.
local function At(x, y, team) return { pos = { x = x, y = y, z = 0 }, team = team } end
local function Seen() return true end

T.test("a sentry targets the nearest enemy it sees within its range", function()
	local far, near, friend = At(600, 0, BLUE), At(300, 0, BLUE), At(100, 0, RED)
	local hidden = At(200, 0, BLUE)
	local sees = function(c) return c ~= hidden end
	T.eq(Buildings.Target({ x = 0, y = 0, z = 0 }, { far, friend, hidden, near }, RED, sees), near, "the nearest seen")
	local beyond = At(Buildings.SENTRY_RANGE + 1, 0, BLUE)
	T.eq(Buildings.Target({ x = 0, y = 0, z = 0 }, { beyond }, RED, Seen), nil, "none beyond its range")
	T.eq(Buildings.Target({ x = 0, y = 0, z = 0 }, { friend }, RED, Seen), nil, "never its own team")
end)

T.test("a sentry turns toward its aim at its turn rate, the short way round", function()
	local step = Buildings.SENTRY_TURN_RATE * 0.1
	T.near(Buildings.Turn(0, 90, 0.1), step, 1e-9, "a step toward it")
	T.near(Buildings.Turn(0, step / 2, 0.1), step / 2, 1e-9, "onto it, not past it")
	T.near(Buildings.Turn(180 - step, -180 + step, 0.1), 180 - step + step, 1e-9, "across the back, not round the front")
	T.near(Buildings.Turn(180 - 2 * step, -180 + 2 * step, 0.1), 180 - step, 1e-9, "a step across the back")
end)

-- The model's aim_yaw turns its gun right and aim_pitch raises it, against Source's angles (yaw to
-- the left, pitch down), as TF2 sets them (tf_obj_sentrygun.cpp MoveTurret).
T.test("a sentry's model shows its aim as pose parameters, against its angles", function()
	local yaw, pitch = Buildings.Pose(90, 30)
	T.eq(yaw, -90, "aimed left: its gun turned left")
	T.eq(pitch, -30, "aimed down: its gun lowered")
	T.eq(select(1, Buildings.Pose(-268, 0)), -92, "a yaw unwound, the short way")
end)

T.test("a sentry fires only once its aim is within its cone of the target", function()
	T.eq(Buildings.OnTarget(0, Buildings.SENTRY_FIRE_CONE / 2), true, "on it")
	T.eq(Buildings.OnTarget(0, Buildings.SENTRY_FIRE_CONE * 2), false, "still turning")
	T.eq(Buildings.OnTarget(179, -179), true, "on it across the back")
end)

T.test("a teleporter carries its own team, once charged again after each trip", function()
	T.eq(Buildings.Carries(RED, RED), true, "its team")
	T.eq(Buildings.Carries(RED, BLUE), false, "never the enemy")
	T.eq(Buildings.Charged(nil, 0), true, "charged before its first trip")
	T.eq(Buildings.Charged(5, 5 + Buildings.TELEPORTER_RECHARGE / 2), false, "recharging")
	T.eq(Buildings.Charged(5, 5 + Buildings.TELEPORTER_RECHARGE), true, "charged")
end)

T.test("a dispenser serves its own team, never the enemy", function()
	T.eq(Buildings.Serves(RED, RED), true, "its team")
	T.eq(Buildings.Serves(RED, BLUE), false, "the enemy")
	T.eq(Buildings.Serves(1001, 1001), true, "its own, without a playing team")
end)

T.test("a dispenser heals at its rate, never past full health", function()
	local rate = Buildings.DISPENSER_HEAL_RATE
	T.eq(Buildings.Dispensed(50, 100, 1), 50 + rate, "a second's healing")
	T.eq(Buildings.Dispensed(50, 100, 0.5), 50 + rate / 2, "half a second's")
	T.eq(Buildings.Dispensed(100 - rate / 2, 100, 1), 100, "full, and no more")
	T.eq(Buildings.Dispensed(100, 100, 1), 100, "already full")
end)

T.test("a dispenser's ammo is a share of what a body may carry, at least a round, up to its most", function()
	T.eq(Buildings.AmmoGiven(0, 100), 100 * Buildings.DISPENSER_AMMO_SHARE, "a share")
	T.eq(Buildings.AmmoGiven(95, 100), 5, "up to its most")
	T.eq(Buildings.AmmoGiven(100, 100), 0, "full")
	T.eq(Buildings.AmmoGiven(0, 2) >= 1, true, "at least a round")
end)

T.test("an access door lets its own team through and stops every other", function()
	T.eq(Buildings.Passes(RED, RED), true, "its team")
	T.eq(Buildings.Passes(RED, BLUE), false, "the enemy")
	T.eq(Buildings.Passes(RED, Teams.UNASSIGNED), false, "nobody's")
end)

T.test("an access door closes the nav areas it stands in to every team but its own", function()
	local barriers = Buildings.Barriers()
	barriers:Add("a", RED, { 10, 11 })
	T.eq(barriers:Blocks(10, BLUE), true, "to the enemy")
	T.eq(barriers:Blocks(11, Teams.UNASSIGNED), true, "to nobody's")
	T.eq(barriers:Blocks(10, RED), false, "open to its own team")
	T.eq(barriers:Blocks(12, BLUE), false, "elsewhere open")
end)

T.test("a door gone opens its areas, but for another door still standing there", function()
	local barriers = Buildings.Barriers()
	barriers:Add("a", RED, { 10, 11 })
	barriers:Add("b", BLUE, { 11 })
	barriers:Remove("a")
	T.eq(barriers:Blocks(10, BLUE), false, "opened")
	T.eq(barriers:Blocks(11, RED), true, "BLU's door still closes it to RED")
	T.eq(barriers:Blocks(11, BLUE), false, "and opens it to BLU")
	barriers:Remove("b")
	barriers:Remove("b")
	T.eq(barriers:Blocks(11, RED), false, "all gone, and a second removal is nothing")
end)

T.test("the tuning of the buildings is defined", function()
	T.defined(Buildings.SENTRY_RANGE, "SENTRY_RANGE")
	T.defined(Buildings.SENTRY_TURN_RATE, "SENTRY_TURN_RATE")
	T.defined(Buildings.SENTRY_FIRE_CONE, "SENTRY_FIRE_CONE")
	T.defined(Buildings.SENTRY_PITCH_MAX, "SENTRY_PITCH_MAX")
	for _, level in ipairs({ 1, 3 }) do
		T.defined(Buildings.SENTRY_LEVELS[level].health, "a level " .. level .. " sentry's health")
		T.defined(Buildings.SENTRY_LEVELS[level].interval, "a level " .. level .. " sentry's interval")
	end
	T.defined(Buildings.SENTRY_LEVELS[3].rocketInterval, "a level 3 sentry's rocket interval")
	T.defined(Buildings.SENTRY_LEVELS[3].rocketDamage, "a level 3 sentry's rocket damage")
	T.defined(Buildings.SENTRY_LEVELS[3].rocketSpeed, "a level 3 sentry's rocket speed")
	T.defined(Buildings.SENTRY_SEARCH_ARC, "SENTRY_SEARCH_ARC")
	T.defined(Buildings.SENTRY_SEARCH_SHARE, "SENTRY_SEARCH_SHARE")
	T.defined(Buildings.SENTRY_FIRE_INTERVAL, "SENTRY_FIRE_INTERVAL")
	T.defined(Buildings.SENTRY_DAMAGE, "SENTRY_DAMAGE")
	T.defined(Buildings.TELEPORTER_RECHARGE, "TELEPORTER_RECHARGE")
	T.defined(Buildings.DOOR_OPEN_REACH, "DOOR_OPEN_REACH")
	T.defined(Buildings.DOOR_CLOSE_DELAY, "DOOR_CLOSE_DELAY")
	T.defined(Buildings.SPAWN_PRICE[Buildings.SENTRY], "a sentry's SPAWN_PRICE")
	T.defined(Buildings.SPAWN_PRICE[Buildings.TELEPORTER], "a teleporter's SPAWN_PRICE")
	T.defined(Buildings.WRENCH_REPAIR, "WRENCH_REPAIR")
	T.defined(Buildings.WRENCH_HURRY, "WRENCH_HURRY")
	T.defined(Buildings.WRENCH_DAMAGE, "WRENCH_DAMAGE")
	T.defined(Buildings.WRENCH_RANGE, "WRENCH_RANGE")
	T.defined(Buildings.WRENCH_INTERVAL, "WRENCH_INTERVAL")
	T.defined(Buildings.TEND_REACH, "TEND_REACH")
	T.defined(Buildings.DISPENSER_RANGE, "DISPENSER_RANGE")
	T.defined(Buildings.DISPENSER_HEAL_RATE, "DISPENSER_HEAL_RATE")
	T.defined(Buildings.DISPENSER_AMMO_SHARE, "DISPENSER_AMMO_SHARE")
	T.defined(Buildings.DISPENSER_AMMO_INTERVAL, "DISPENSER_AMMO_INTERVAL")
	T.defined(Buildings.SPAWN_PRICE[Buildings.DISPENSER], "a dispenser's SPAWN_PRICE")
end)

T.finish()
