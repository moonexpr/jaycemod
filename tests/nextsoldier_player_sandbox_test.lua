-- nextsoldier.player.sandbox: the default AI of a sandbox player, a CLuaNextBotPlayer
-- class (sandbox_player) whose tree is SandboxMainAction > TacticalMonitor > MissionMonitor >
-- the mission it is on. Its first mission, wander: from hiding spot to hiding spot about the
-- map, hiding a while at each. Over fakes of the engine, the player and the world it reads
-- (its hiding spots, the routes between them).
local T = dofile ("tests/harness.lua")
local Player = nextsoldier.player
local Sandbox = nextsoldier.player.sandbox
local Puppets = nextsoldier.player.puppets
local Behavior = generator.state_chart.Behavior

local VecMeta = {}
VecMeta.__index = VecMeta
function VecMeta:Length2D () return math.sqrt (self.x * self.x + self.y * self.y) end
local function Vec (x, y, z) return setmetatable ({ x = x, y = y, z = z or 0 }, VecMeta) end

local function FakePlayer ()
	local ply = { pos = Vec (0, 0, 0), alive = true }
	function ply:GetTable () return self end
	function ply:GetClass () return "player" end
	function ply:Alive () return self.alive end
	function ply:GetPos () return self.pos end
	function ply:EyePos () return Vec (self.pos.x, self.pos.y, self.pos.z + 64) end
	function ply:EyeAngles () return { p = 0, y = 0, r = 0 } end
	function ply:IsOnGround () return true end
	function ply:Crouching () return false end
	function ply:GetVelocity () return Vec (0, 0, 0) end
	return ply
end

local function FakeEngine ()
	local engine = { inserted = {} }
	function engine.Insert (bot, action, me) engine.inserted [#engine.inserted + 1] = action end
	function engine.End () end
	function engine.Stack () return {} end
	function engine.GroupStack () return {} end
	function engine.Puppet () return {} end
	return engine
end

-- A world of hiding spots, whose routes run straight from where a body stands to where it is
-- going (unless `blocked` names the goal), and whose draws are given in turn (else the first).
local function FakeWorld (spots)
	local world = { spots = spots, blocked = {}, draws = {}, planned = {} }
	function world.HidingSpots () return world.spots end
	function world.PlanRoute (from, goal)
		world.planned [#world.planned + 1] = goal
		if world.blocked [goal] then return nil end
		return { from, goal }
	end
	function world.CanWalk () return true end
	function world.Random (low, high)
		local draw = table.remove (world.draws, 1) or low
		assert (draw >= low and draw <= high, "a draw in range")
		return draw
	end
	return world
end

-- A sandbox bot, its world and clock, and its tree run as the chart runs an engine's.
local function Made (spots)
	local clock = { now = 10 }
	local services =
	{
		Engine = FakeEngine (),
		CreateBot = function () return FakePlayer () end,
		Now = function () return clock.now end,
		Angle = function (p, y, r) return { p = p, y = y, r = r } end,
		RunConCommand = function () return false end,
		AddHook = function () end
	}
	Player.Install (services)
	local world = FakeWorld (spots or { Vec (1000, 0, 0), Vec (0, 1000, 0), Vec (-1000, 0, 0) })
	Sandbox.Install (world)
	local ply = Player.Create ("sandbox_player", "Wanderer")
	local tree = Behavior:New (services.Engine.inserted [1], "test")
	local bot = { ply = ply, world = world, clock = clock, tree = tree }
	-- one update of its tree, the clock run on by dt
	function bot:Tick (dt)
		self.clock.now = self.clock.now + (dt or 0.1)
		self.tree:Update (self.ply, dt or 0.1)
	end
	-- the names on its stack, outermost first
	function bot:Stack ()
		local names = {}
		for _, frame in ipairs (self.tree:Stack ()) do names [#names + 1] = frame.name end
		return table.concat (names, " > ")
	end
	return bot
end

T.test ("the world the sandbox player reads is held to its port", function ()
	T.eq (pcall (Sandbox.Install, {}), false, "a world lacking its methods is refused")
end)

T.test ("its tree is SandboxMainAction > TacticalMonitor > MissionMonitor > the mission's", function ()
	local bot = Made ()
	bot:Tick ()
	T.eq (bot:Stack (),     "SandboxMainAction > TacticalMonitor > MissionMonitor > SandboxGoToHidingSpot", "its stack")
	T.eq (bot.ply.Behavior, "SandboxMainAction", "the class names its root")
end)

T.test ("wandering, it walks a route planned to a hiding spot it drew", function ()
	local bot = Made ()
	bot.world.draws = { 2 }
	bot:Tick ()
	T.eq (bot.world.planned [1],   bot.world.spots [2], "a route to the spot drawn")
	T.eq (bot.ply.state.loco.goal, bot.world.spots [2], "it makes for it")
end)

T.test ("there, it hides crouched a while, then goes on to another spot", function ()
	local bot = Made ()
	bot.world.draws = { 1 }
	bot:Tick ()
	bot.ply.pos = bot.world.spots [1]
	bot.world.draws = { 12 }
	bot:Tick ()
	T.eq (bot:Stack ():match ("[%w]+$"),            "SandboxHide",       "hiding")
	T.eq (Puppets.Body:GetDesiredPosture (bot.ply), Puppets.Body.CROUCH, "crouched")
	T.eq (bot.ply.state.loco.goal,                  nil,                 "still")
	bot:Tick (11)
	T.eq (bot:Stack ():match ("[%w]+$"), "SandboxHide", "not yet: it drew 12 seconds")
	bot.world.draws = { 1 }
	bot:Tick (2)
	T.eq (bot:Stack ():match ("[%w]+$"),                  "SandboxGoToHidingSpot", "then on")
	T.eq (Puppets.Body:GetDesiredPosture (bot.ply),       Puppets.Body.STAND,      "standing")
	T.eq (bot.ply.state.loco.goal ~= bot.world.spots [1], true,                    "to another spot than this one")
end)

T.test ("its hiding time is drawn within its profile's", function ()
	local bot = Made ()
	local profile = bot.ply.SandboxDefaults
	T.defined (profile.HideMin, "HideMin")
	T.defined (profile.HideMax, "HideMax")
	bot.world.draws = { 1 }
	bot:Tick ()
	bot.ply.pos = bot.world.spots [1]
	local asked
	local draw = bot.world.Random
	bot.world.Random = function (low, high)
		asked = { low = low, high = high }
		return draw (low, high)
	end
	bot:Tick ()
	T.eq (asked.low,  profile.HideMin, "from its least")
	T.eq (asked.high, profile.HideMax, "to its most")
end)

T.test ("a spot with no route there is passed over for another", function ()
	local bot = Made ()
	bot.world.blocked [bot.world.spots [1]] = true
	bot.world.draws = { 1, 1 }
	bot:Tick ()
	T.eq (bot.world.planned [1], bot.world.spots [1], "it tried the first")
	bot:Tick ()
	T.eq (bot.world.planned [2] ~= bot.world.spots [1], true,                  "then not that one again")
	T.eq (bot.ply.state.loco.goal,                      bot.world.planned [2], "and makes for the other")
end)

T.test ("a walk that stalls is given up for another spot", function ()
	local bot = Made ()
	bot.world.draws = { 1 }
	bot:Tick ()
	bot:Tick (nextsoldier.locomotion.route_walk.STALL_TIME + 1)
	bot:Tick ()
	T.eq (#bot.world.planned >= 2,                                       true, "it planned again")
	T.eq (bot.world.planned [#bot.world.planned] ~= bot.world.spots [1], true, "elsewhere")
end)

T.test ("with no hiding spots it stands, and looks again a while later", function ()
	local bot = Made ({})
	bot:Tick ()
	T.eq (bot.ply.state.loco.goal, nil, "nowhere to go")
	bot.world.spots = { Vec (500, 0, 0) }
	bot:Tick (0.1)
	T.eq (bot.ply.state.loco.goal, nil, "not at once")
	bot:Tick (Sandbox.wander.RETRY)
	T.eq (bot.ply.state.loco.goal, bot.world.spots [1], "it found one")
end)

T.test ("its one spot is gone to again, there being no other", function ()
	local bot = Made ({ Vec (500, 0, 0) })
	bot:Tick ()
	T.eq (bot.ply.state.loco.goal, bot.world.spots [1], "the only one")
end)

T.test ("a mission is one registered; the monitor changes to the one it chooses", function ()
	T.eq (pcall (Sandbox.Mission, "no_such_mission"), false, "an unknown one refused")
	local Patrol = nextsoldier.behavior.action.Extend ("TestSandboxPatrol")
	Sandbox.RegisterMission ("test_patrol", function () return Patrol:New () end)
	local bot = Made ()
	bot:Tick ()
	bot.ply.SandboxDefaults.Mission = "test_patrol"
	bot:Tick ()
	bot:Tick ()
	T.eq (bot:Stack (), "SandboxMainAction > TacticalMonitor > MissionMonitor > TestSandboxPatrol", "the new mission")
end)

T.finish ()
