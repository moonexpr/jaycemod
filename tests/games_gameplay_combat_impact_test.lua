local T = dofile("tests/harness.lua")
local Teams = gameplay.teams
local Impact = T.require("games.gameplay.combat.impact")

T.test("the tuning is defined", function()
	T.defined(Impact.WINDOW, "window")
	T.defined(Impact.MIN_SPEED, "least speed")
	T.defined(Impact.DAMAGE_PER_SPEED, "damage per speed")
	T.defined(Impact.MAX_DAMAGE, "most damage")
	T.defined(Impact.WALL_NORMAL_Z, "what is a wall")
	T.defined(Impact.STOP_FRACTION, "what is a stop")
end)

-- The operator's rule: you cannot be injured by pushing yourself or a
-- teammate into a wall.
T.test("an enemy's throw harms; one's own and a teammate's do not", function()
	T.eq(Impact.Harms(Teams.RED, Teams.BLUE, false), true, "enemy")
	T.eq(Impact.Harms(Teams.RED, Teams.RED, false), false, "teammate")
	T.eq(Impact.Harms(Teams.RED, Teams.RED, true), false, "self")
end)

T.test("walls and ceilings are struck; floors are fall damage's", function()
	T.eq(Impact.Struck(0), true, "a wall")
	T.eq(Impact.Struck(-1), true, "a ceiling")
	T.eq(Impact.Struck(1), false, "a floor")
	T.eq(Impact.Struck(Impact.WALL_NORMAL_Z), false, "as steep as a floor gets")
end)

T.test("no damage below the least speed into the surface", function()
	T.eq(Impact.Damage(0), 0, "still")
	T.eq(Impact.Damage(Impact.MIN_SPEED), 0, "at it")
end)

T.test("damage rises with the speed past the least, to the most", function()
	local a = Impact.Damage(Impact.MIN_SPEED + 100)
	local b = Impact.Damage(Impact.MIN_SPEED + 200)
	T.near(a, 100 * Impact.DAMAGE_PER_SPEED, 1e-9, "linear")
	T.eq(b > a, true, "faster hurts more")
	T.eq(Impact.Damage(1e9), Impact.MAX_DAMAGE, "capped")
end)

T.test("the speed into a surface is along its normal, none when leaving it", function()
	T.eq(Impact.Into({ x = 800, y = 0, z = 0 }, { x = -1, y = 0, z = 0 }), 800, "head on")
	T.near(Impact.Into({ x = 800, y = 800, z = 0 }, { x = -1, y = 0, z = 0 }), 800, 1e-9, "glancing: only the part into it")
	T.eq(Impact.Into({ x = -800, y = 0, z = 0 }, { x = -1, y = 0, z = 0 }), 0, "moving away")
end)

T.test("a throw is stopped when its speed falls to the stop fraction in a tick", function()
	T.eq(Impact.Stopped(1000, 1000 * Impact.STOP_FRACTION), true, "at it")
	T.eq(Impact.Stopped(1000, 0), true, "dead stop")
	T.eq(Impact.Stopped(1000, 1000 * Impact.STOP_FRACTION + 1), false, "slowing")
	T.eq(Impact.Stopped(0, 0), false, "never moving")
end)

T.finish()
