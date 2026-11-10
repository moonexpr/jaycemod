local T = dofile("tests/harness.lua")

-- ws_bot_navigator over fakes of the nav mesh: whether it knows where its owner stands.
local function Vec(x, y, z)
	local v = { x = x, y = y, z = z }
	function v:DistToSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end
	return v
end

-- An area across the ground from lo to hi on x.
local function Area(lo, hi)
	local area = {}
	function area:GetClosestPointOnArea(p)
		return Vec(math.min(hi, math.max(lo, p.x)), p.y, p.z)
	end
	return area
end

local nearest
local clock = 0
local ENT = {}
local environment = setmetatable({
	ENT = ENT,
	SERVER = true,
	CLIENT = false,
	AddCSLuaFile = function() end,
	IsValid = function(value) return value ~= nil end,
	hook = { Add = function() end },
	CurTime = function() return clock end,
	navmesh = { GetNearestNavArea = function() return nearest end },
}, { __index = _G })
setfenv(assert(loadfile("addons/sandcastle/gamemodes/wetsands/entities/entities/ws_bot_navigator.lua")), environment)()

local function Navigator(at, last)
	local navigator = setmetatable({}, { __index = ENT })
	function navigator:GetOwner() return { GetPos = function() return at end } end
	function navigator:GetLastKnownArea() return last end
	return navigator
end

local WEST, EAST = Area(-400, -200), Area(-200, -100)

T.test("on the area its owner stands on, it is settled", function()
	nearest = EAST
	T.eq(Navigator(Vec(-150, 0, 0), EAST):Settled(), true, "the same area")
end)

T.test("on the seam between two areas, either of them is where it stands", function()
	-- ctf_2fort's x = -200: the engine keeps the one it was on, the search says the other
	nearest = WEST
	T.eq(Navigator(Vec(-200.004, 0, 0), EAST):Settled(), true, "it would never settle")
end)

T.test("an owner set down elsewhere is not settled until its area catches up", function()
	nearest = WEST
	T.eq(Navigator(Vec(-350, 0, 0), EAST):Settled(), false, "its last area is behind it")
end)

T.test("no area near its owner, there is nothing to wait for", function()
	nearest = nil
	T.eq(Navigator(Vec(0, 0, 0), EAST):Settled(), true, "off the mesh")
end)

T.test("no last area yet, and one is near, it waits", function()
	nearest = WEST
	T.eq(Navigator(Vec(-350, 0, 0), nil):Settled(), false, "the engine has not told it")
end)

T.test("it does not wait for ever on an area the engine will not catch up to", function()
	nearest = EAST
	clock = 100
	-- the owner stands well inside EAST, and the engine keeps WEST: a body it found no floor under
	local navigator = Navigator(Vec(-150, 0, 0), WEST)
	T.eq(navigator:Settled(), false, "a moment to catch up, as when set down elsewhere")
	clock = 100 + environment.ENT.SETTLE_PATIENCE - 0.01
	T.eq(navigator:Settled(), false, "still within it")
	clock = 100 + environment.ENT.SETTLE_PATIENCE
	T.eq(navigator:Settled(), true, "planning from where it knows is better than never planning")
end)

T.test("having caught up, its patience starts over", function()
	nearest = EAST
	clock = 200
	local last = WEST
	local navigator = setmetatable({}, { __index = ENT })
	function navigator:GetOwner() return { GetPos = function() return Vec(-150, 0, 0) end } end
	function navigator:GetLastKnownArea() return last end
	T.eq(navigator:Settled(), false, "waiting")
	last = EAST
	clock = 200.1
	T.eq(navigator:Settled(), true, "caught up")
	last = WEST
	clock = 300
	T.eq(navigator:Settled(), false, "set down elsewhere much later: a moment again")
end)

T.finish()
