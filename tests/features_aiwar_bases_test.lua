-- The AI war's Bases (features/aiwar/sv_field.lua): a game's spawns may not
-- exist yet (a built layout's are made again after a cleanup), so a survey
-- that finds a team without any is not kept, or the war would wait for them
-- for good.
local T = dofile("tests/harness.lua")
local Teams = gameplay.teams
local RED, BLUE = Teams.RED, Teams.BLUE

local Vec = {}
Vec.__index = Vec
Vec.__add = function(a, b) return setmetatable({ x = a.x + b.x }, Vec) end
Vec.__div = function(a, n) return setmetatable({ x = a.x / n }, Vec) end
local function Vector(x) return setmetatable({ x = x }, Vec) end
local function Spot(x) return { GetPos = function() return Vector(x) end } end

local function Controller(spots)
	local controller = {}
	local Map = {
		RED = RED,
		BLUE = BLUE,
		Point = function(pos) return { x = pos.x } end,
		GroundBelow = function(pos) return pos end,
		SpawnSpots = function(team) return spots[team] end,
	}
	local env = setmetatable({
		WS = { require = T.require },
		Vector = Vector,
		hook = { Add = function() end },
	}, { __index = _G })
	setfenv(assert(loadfile(T.ROOT .. "features/aiwar/sv_field.lua")), env)(controller, Map, 1)
	return controller
end

T.test("spawns found for both teams are kept", function()
	local spots = { [RED] = { Spot(10) }, [BLUE] = { Spot(30) } }
	local controller = Controller(spots)
	T.eq(controller:Bases().bases[BLUE].x, 30, "the base")
	spots[BLUE] = { Spot(99) }
	T.eq(controller:Bases().bases[BLUE].x, 30, "kept until the next round")
end)

T.test("a team without spawns is looked for again, and found once made", function()
	local spots = { [RED] = { Spot(10) }, [BLUE] = {} }
	local controller = Controller(spots)
	T.eq(controller:Bases().bases[BLUE], nil, "none yet")
	spots[BLUE] = { Spot(30) }
	T.eq(controller:Bases().bases[BLUE].x, 30, "made since")
end)

T.finish()
