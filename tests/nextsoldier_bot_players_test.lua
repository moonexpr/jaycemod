local T = dofile("tests/harness.lua")

-- The bot player's soldier (sv_next_soldiers.lua) over fakes of the player and the
-- engine: what it sweeps with and what it prices its routes by.
local Vec
local Methods = {}
function Methods:Distance(other) return math.geometry.Distance(self, other) end
local Meta = {
	__index = Methods,
	__add = function(a, b) return Vec(a.x + b.x, a.y + b.y, a.z + b.z) end,
	__sub = function(a, b) return Vec(a.x - b.x, a.y - b.y, a.z - b.z) end,
}
Vec = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, Meta) end

local swept, planned, asked, ready
local verdicts = {}
local navigator = {
	Settled = function() return true end,
	PlanRoute = function(_, _, cost) planned = cost return { Vec(0, 0, 0), Vec(100, 0, 0) } end,
}
local function ValidPlayer()
	local ply = { NSNavigator = navigator }
	function ply:GetPos() return Vec(0, 0, 0) end
	function ply:Team() return 3 end
	function ply:EntIndex() return 7 end
	function ply:GetHull() return Vec(-24, -24, 0), Vec(24, 24, 82) end
	function ply:GetClass() return "player" end
	return ply
end
local added
local hooks = {}
local environment = setmetatable({
	Vector = Vec,
	IsValid = function(value) return value ~= nil end,
	CurTime = function() return 1 end,
	MASK_PLAYERSOLID = 1,
	util = { TraceHull = function(trace) swept = trace return { Hit = false } end, TraceLine = function() return { Hit = true } end },
	navmesh = { GetNearestNavArea = function() return nil end },
	hook = { Add = function(name, _, run) hooks[name] = run end },
	concommand = { Add = function() end },
	player = { CreateNextSoldier = function() return added end },
	wartactics = { scenarios = {} },
	WS = {
		TEAM_RED = 2,
		TEAM_BLUE = 3,
		SetPlayerTeam = function() end,
		require = function(name)
			if name == "features.flag.soldier" then return { Apply = function() end } end
			return T.require(name)
		end,
		ClipMasks = function() return { brushes = 1 } end,
		NavHullClearance = function()
			return {
				Area = function(_, area) return area ~= "narrow" end,
				Link = function(_, _, area) return area ~= "behind a frame" end,
			}
		end,
		Feature = function()
			return {
				EngineCost = function(_, team, strategy, limits, bot)
					asked = { team = team, strategy = strategy, limits = limits, bot = bot }
					return ready and function(area, fromArea, ladder, elevator, length, fits)
						verdicts[area] = fits
						return 1
					end or nil
				end,
			}
		end,
	},
	nextsoldier = setmetatable({
		engine = {
			Insert = function() end,
			Stack = function() return { { name = "TacticalMonitor", depth = 1 } } end,
		},
		behavior = {
			action = nextsoldier.behavior.action,
			ctfbot = { Compile = function() return {} end, InitialAction = function() return {} end },
		},
	}, { __index = nextsoldier }),
}, { __index = _G })

setfenv(assert(loadfile(T.ROOT .. "sv_next_soldiers.lua")), environment)()

local function New()
	added = ValidPlayer()
	function added:KillSilent() end
	function added:Nick() return "bot" end
	local soldier
	environment.WS.AddNextSoldier(3, "bot")
	soldier = environment.WS.NextSoldierOf(added)
	return soldier
end

T.test("its walks are swept with its own width, not a narrower box", function()
	local soldier = New()
	soldier:WalkClear(Vec(0, 0, 0), Vec(100, 0, 0))
	T.eq(swept.mins.x, -24, "its shoulders, which catch on door frames")
	T.eq(swept.maxs.y, 24, "its shoulders, the other way")
end)

T.test("its routes are priced as TF2's bots are, over what its team knows", function()
	ready, planned = true, nil
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(asked.strategy, T.require("foundation.wetsands.path.tfbot"), "CTFBotPathCost")
	T.eq(asked.team, 3, "its team's")
	T.eq(asked.bot.team, 3, "its team's spawn rooms are its own")
	T.eq(planned ~= nil, true, "the route is priced")
end)

T.test("each step is told whether its body fits", function()
	ready, planned = true, nil
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	planned("open", "from")
	planned("narrow", "from")
	planned("behind a frame", "from")
	planned("up a ladder", "from", "ladder")
	T.eq(verdicts["open"], true, "room to pass")
	T.eq(verdicts["narrow"], false, "its body does not stand there")
	T.eq(verdicts["behind a frame"], false, "its shoulders catch on the way in")
	T.eq(verdicts["up a ladder"], true, "a ladder crosses no opening")
end)

T.test("no route is planned until the mesh is ready", function()
	ready, planned = false, nil
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(planned, nil, "a route without its price would walk into what TF2's refuses")
end)

T.test("a route's drop right below it is stepped off, past the ledge, not stood over", function()
	ready, planned = true, nil
	local soldier = New()
	local ledge = 30
	environment.util.TraceHull = function(trace)
		-- the floor ends at the ledge, and the landing lies far below it
		if trace.start.z == trace.endpos.z then return { Hit = false } end
		if trace.start.x + trace.mins.x < ledge then return { Hit = true, HitPos = trace.start } end
		if trace.endpos.z < -100 then return { Hit = true, HitPos = Vec(trace.start.x, trace.start.y, -188) } end
		return { Hit = false }
	end
	soldier.walk = {
		Stalled = function() return false end,
		Next = function() return { x = 20, y = 0, z = -188 } end,
	}
	soldier.planned = Vec(5000, 0, 0)
	soldier.nextPlan = 100
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(soldier.steer.z, 0, "a point on its own level")
	T.eq(soldier.steer.x - 24 >= ledge, true, "its whole body past the edge")
end)

T.test("a jamb beside its way veers its steering away", function()
	ready, planned = true, nil
	local soldier = New()
	environment.util.TraceHull = function(trace)
		-- going +x, its left is +y: a wall along that side
		return { Hit = trace.start.y > 0 }
	end
	soldier.walk = {
		Stalled = function() return false end,
		Next = function() return { x = 500, y = 0, z = 0 } end,
	}
	soldier.planned = Vec(5000, 0, 0)
	soldier.nextPlan = 100
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(soldier.steer.y < 0, true, "toward the open side")
end)

local function Route(points)
	navigator.PlanRoute = function(_, _, cost) planned = cost return points end
end

-- A pillar at x = 100 on the route's line: a floor everywhere, no wall but it.
local function BesidePillar(gap)
	environment.util.TraceHull = function(trace)
		local at = trace.start
		-- the engine reads a box only from Vectors: anything else sweeps a point
		local half = getmetatable(trace.mins) == Meta and 24 or 0
		return { Hit = trace.start.x == trace.endpos.x and trace.start.y == trace.endpos.y
			and math.abs(at.x - 100) < half and math.abs(at.y) < half }
	end
	environment.util.TraceLine = function(trace)
		if trace.start.z ~= trace.endpos.z then return { Hit = not gap } end
		return { Hit = false }
	end
end

T.test("a route's point its body does not fit on is walked to where it does", function()
	ready, planned = true, nil
	BesidePillar(false)
	Route({ Vec(0, 0, 0), Vec(100, 0, 0), Vec(500, 0, 0) })
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	local point = soldier.walk.points[2]
	T.eq(math.abs(point.x - 100) >= 24 or math.abs(point.y) >= 24, true, "clear of the pillar")
end)

T.test("nor is a point moved off the floor to fit", function()
	ready, planned = true, nil
	BesidePillar(true)
	Route({ Vec(0, 0, 0), Vec(100, 0, 0), Vec(500, 0, 0) })
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(soldier.walk.points[2].x, 100, "no floor anywhere near: left as planned")
	T.eq(soldier.walk.points[2].y, 0, "left as planned")
end)

T.test("the debug layer shows a bot player's engine stack", function()
	local soldier = New()
	local found = {}
	hooks.WSNbDebugNpcs(found)
	local name, frames = found[soldier.ent]:Stack()
	T.eq(name, "player", "its class")
	T.eq(frames[1].name, "TacticalMonitor", "what the engine runs")
end)

-- A command as Drive writes it: what the engine's move reads.
local function Command()
	local cmd = {}
	function cmd:SetViewAngles(angles) self.view = angles end
	function cmd:SetForwardMove(speed) self.forward = speed end
	function cmd:SetSideMove(speed) self.side = speed end
	function cmd:SetButtons(buttons) self.buttons = buttons end
	return cmd
end

-- A soldier told to walk +y, with its eyes along +x.
local function Driven()
	local soldier = New()
	local ply = soldier.ent
	function ply:EyeAngles() return { p = 3, y = 0, r = 0 } end
	function ply:EyePos() return Vec(0, 0, 64) end
	function ply:GetVelocity() return { Length2D = function() return 0 end, z = 0 } end
	function ply:OnGround() return true end
	function ply:GetRunSpeed() return 300 end
	function ply:SetEyeAngles() self.eyesSet = true end
	soldier.nextSteer = 100
	soldier.steer = { x = 0, y = 500, z = 0 }
	return soldier
end

T.test("its feet go their way whatever its eyes look at", function()
	environment.Angle = function(p, y, r) return { p = p, y = y, r = r } end
	environment.engine = { TickInterval = function() return 0.015 end }
	environment.bit = { bor = function(a, b) return a + b end }
	local soldier = Driven()
	local cmd = Command()
	soldier.head = true
	soldier:Drive(cmd)
	T.eq(cmd.view.y, 0, "looking where its head was left looking")
	T.eq(math.abs(cmd.forward) < 0.001, true, "not forward: its way is off to the side")
	T.eq(cmd.side < -299, true, "to its left, a negative side move")
	T.eq(soldier.ent.eyesSet, nil, "its eyes are the head's to set")
end)

T.test("with no head its eyes go where it walks, as they did", function()
	local soldier = Driven()
	local cmd = Command()
	soldier:Drive(cmd)
	T.eq(cmd.view.y, 90, "along its way")
	T.eq(cmd.forward, 300, "forward")
end)

T.test("a soldier's head is given its config as it is added", function()
	local given
	environment.nextsoldier.engine.Look = function(_, config) given = config end
	environment.GetConVar = function() return { GetFloat = function() return 0.5 end } end
	environment.engine = { TickInterval = function() return 0.015 end }
	local soldier = New()
	T.eq(soldier.head, true, "its head is Rust's")
	T.eq(given.interval, 0.015, "ticked at the server's rate")
	T.eq(given.settle, 0.5, "the engine's own convars")
	T.eq(given.sources[1].kind, "BodyFacing", "what makes it look")
	environment.nextsoldier.engine.Look = nil
end)

T.test("the debug layer reads its head's lines, only when it has one", function()
	local soldier = New()
	local found = {}
	hooks.WSNbDebugNpcs(found)
	T.eq(found[soldier.ent].LookLines, nil, "no head, no lines")
	soldier.head, soldier.debug = true, nil
	environment.nextsoldier.engine.LookLines = function(_, name, now) return { name .. " " .. now } end
	function soldier.ent:Nick() return "bot" end
	hooks.WSNbDebugNpcs(found)
	T.eq(found[soldier.ent]:LookLines(7)[1], "bot 7", "its name and the game's time")
end)

T.finish()
