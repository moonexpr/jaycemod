-- nextsoldier.player.sandbox: the default AI of a sandbox player, a CLuaNextBotPlayer
-- class (sandbox_player) whose tree is the binary's acts, SandboxMainAction > TacticalMonitor >
-- MissionMonitor > the mission it is on (wander: SandboxGoToHidingSpot, SandboxHide), each a
-- config its engine constructor makes. The acts themselves are tested in Rust
-- (addons/nextsoldier/native/src/behavior/); here, the configs the class makes, the methods the
-- acts read it through (act_bind.rs's SoldierLua), and its fall back without the binary. Over
-- fakes of the engine, the player and the world it reads.
local T = dofile ("tests/harness.lua")
local Player = nextsoldier.player
local Sandbox = nextsoldier.player.sandbox

local VecMeta = {}
VecMeta.__index = VecMeta
function VecMeta:Length2D () return math.sqrt (self.x * self.x + self.y * self.y) end
-- fn refused, its error naming what.
local function Raises (fn, what)
	local ok, err = pcall (fn)
	T.eq (ok,                                         false, "refused: " .. what)
	T.eq (tostring (err):find (what, 1, true) ~= nil, true,  "names " .. what .. ": " .. tostring (err))
end

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

-- The native kinds the class makes, each a constructor recording its config.
local KINDS =
{
	"SandboxMainAction",
	"TacticalMonitor",
	"MissionMonitor",
	"SandboxGoToHidingSpot",
	"SandboxHide",
	"SandboxGoToSite",
	"SandboxBuild",
	"SandboxDefend"
}

-- An engine the bot is inserted into; bound, it has the sandbox's kinds.
local function FakeEngine (bound)
	local engine = { inserted = {} }
	function engine.Insert (bot, action, me) engine.inserted [#engine.inserted + 1] = action end
	function engine.End () end
	function engine.Stack () return {} end
	function engine.GroupStack () return {} end
	function engine.Puppet () return {} end
	if bound then
		for _, kind in ipairs (KINDS) do
			engine [kind] = function (config) return { kind = kind, config = config } end
		end
	end
	return engine
end

-- A world of hiding spots, whose routes run straight (unless `blocked` names the goal), and
-- whose draws are given in turn (else the first).
local function FakeWorld (spots)
	local world = { spots = spots, open = { Vec (5000, 0, 0), Vec (0, 5000, 0) }, blocked = {}, draws = {}, planned = {} }
	function world.HidingSpots () return world.spots end
	function world.OpenGround (width)
		world.width = width
		return world.open
	end
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

-- A sandbox bot, its world, and the root it was inserted with.
-- A builder whose blocks stand until knocked down (`gone`).
local function FakeBuilder ()
	local builder = { spawned = {}, gone = {} }
	function builder.Spawn (block, owner)
		builder.spawned [#builder.spawned + 1] = { block = block, owner = owner }
		return #builder.spawned
	end
	function builder.Standing (handle) return not builder.gone [handle] end
	return builder
end

local function Made (bound, class)
	local engine = FakeEngine (bound ~= false)
	Player.Install (
		{
			Engine = engine,
			CreateBot = function () return FakePlayer () end,
			Now = function () return 10 end,
			Angle = function (p, y, r) return { p = p, y = y, r = r } end,
			RunConCommand = function () return false end,
			AddHook = function () end
		}
	)
	local world = FakeWorld ({ Vec (1000, 0, 0), Vec (0, 1000, 0), Vec (-1000, 0, 0) })
	Sandbox.Install (world)
	local builder = FakeBuilder ()
	Sandbox.InstallBuilder (builder)
	local ply = Player.Create (class or "sandbox_player", "Wanderer")
	return ply, world, engine.inserted [1], builder
end

T.test ("the world the sandbox player reads is held to its port", function ()
	Raises (function () Sandbox.Install ({ HidingSpots = function () end }) end, "PlanRoute")
end)

T.test ("its tree is SandboxMainAction > TacticalMonitor > MissionMonitor, made by the binary", function ()
	local ply, _, root = Made ()
	T.eq (root.kind,                 "SandboxMainAction", "its root")
	T.eq (root.config.tactical.kind, "TacticalMonitor",   "over CTFBot's tactical monitor")
	local monitor = root.config.tactical.config.scenario
	T.eq (monitor.kind,      "MissionMonitor", "its scenario, the mission it is on")
	T.eq (ply.state.unbound, nil,              "bound")
	local place = monitor.config.choose (ply)
	T.eq (place,                                      Sandbox.Place ("wander"), "wander, its profile's")
	T.eq (monitor.config.missions [place] (ply).kind, "SandboxGoToHidingSpot",  "the mission's first action")
end)

T.test ("wander goes to a spot, hides there, and goes on again", function ()
	local ply, _, root = Made ()
	local missions = root.config.tactical.config.scenario.config.missions
	local go = missions [Sandbox.Place ("wander")] (ply)
	local hide = go.config.hide (ply)
	T.eq (hide.kind,                 "SandboxHide",           "there, it hides")
	T.eq (hide.config.go (ply).kind, "SandboxGoToHidingSpot", "then goes on")
end)

T.test ("a mission chosen that none registered is none", function ()
	local ply, _, root = Made ()
	ply.SandboxDefaults = { Mission = "nowhere", HideMin = 1, HideMax = 2 }
	T.eq (root.config.tactical.config.scenario.config.choose (ply), nil, "no mission")
end)

T.test ("a mission is one registered, its place kept when registered again", function ()
	local place = Sandbox.Place ("wander")
	local first = Sandbox.Mission ("wander")
	Sandbox.RegisterMission ("wander", first)
	T.eq (Sandbox.Place ("wander"), place, "the same place")
	Raises (function () Sandbox.Mission ("nowhere") end,        "no sandbox mission")
	Raises (function () Sandbox.RegisterMission (1, first) end, "by a name")
	Raises (function () Sandbox.RegisterMission ("x", 1) end,   "first action")
end)

T.test ("with no SandboxMainAction in the binary, it runs the base's root and says why", function ()
	local ply, _, root = Made (false)
	T.eq (ply.state.unbound,                  "nextsoldier.engine has no SandboxMainAction", "why")
	T.eq (root.kind,                          nil,                                           "no native config")
	T.eq (type (root.InitialContainedAction), "function",                                    "the base's NextBotPlayer")
end)

T.test ("its hiding spots, by place from 1: how many, the last, those avoided", function ()
	local ply = Made ()
	T.eq (ply:HidingSpotCount (), 3,   "three")
	T.eq (ply:LastSpot (),        nil, "none yet")
	ply:SetLastSpot (2)
	T.eq (ply:LastSpot (), 2,     "the last it hid at")
	T.eq (ply:Avoided (3), false, "not avoided")
	ply:Avoid (3)
	T.eq (ply:Avoided (3), true, "avoided")
	ply:ForgetAvoided ()
	T.eq (ply:Avoided (3), false, "forgotten")
end)

T.test ("to a spot, it walks the route its world plans; none, and it goes nowhere", function ()
	local ply, world = Made ()
	T.eq (ply:MoveToSpot (2), true,            "a route")
	T.eq (world.planned [1],  world.spots [2], "planned by its world")
	T.eq (ply:Movement (),    "moving",        "under way")
	world.blocked [world.spots [3]] = true
	T.eq (ply:MoveToSpot (3), false,  "no route")
	T.eq (ply:Movement (),    "idle", "going nowhere")
end)

T.test ("its draws are its world's, and it crouches through its body", function ()
	local ply, world = Made ()
	world.draws = { 4 }
	T.eq (ply:Random (1, 9), 4, "its world's draw")
	ply:Crouch (true)
	T.eq (ply.state.body.posture, nextsoldier.player.puppets.Body.CROUCH, "crouched")
	ply:Crouch (false)
	T.eq (ply.state.body.posture, nextsoldier.player.puppets.Body.STAND, "standing")
end)

-- Every method the binary's acts call on the bot (act_bind.rs's SoldierLua), and every profile
-- field they read, the class has.
T.test ("the class answers every method and profile field the acts read", function ()
	local source = io.open ("addons/nextsoldier/native/src/act_bind.rs"):read ("*a")
	local ply = Made ()
	local methods, fields = 0, 0
	for call, name in source:gmatch ("self%.(%a+)%(c\"(%u%a+)\"") do
		if call ~= "profile" then
			methods = methods + 1
			T.eq (type (ply [name]), "function", name)
		end
	end
	for table_, field in source:gmatch ("profile%(c\"(%a+)\",%s*c\"(%a+)\"") do
		fields = fields + 1
		T.defined (ply [table_] [field], table_ .. "." .. field)
	end
	T.eq (methods >= 15 and fields >= 3, true, "found them")
	T.defined (ply.BatteryDefaults.SprintCost, "the sprint it spends")
end)

-- The build mission: a base blocked out on open ground, built a block at a time, then held.

T.test ("the build mission goes to a site, builds, holds, and back", function ()
	local ply, _, root = Made ()
	local missions = root.config.tactical.config.scenario.config.missions
	local go = missions [Sandbox.Place ("build")] (ply)
	T.eq (go.kind, "SandboxGoToSite", "first, a site")
	local build = go.config.build (ply)
	T.eq (build.kind, "SandboxBuild", "there, it builds")
	local defend = build.config.defend (ply)
	T.eq (defend.kind,                    "SandboxDefend",   "built, it holds")
	T.eq (defend.config.build (ply).kind, "SandboxBuild",    "repairs")
	T.eq (defend.config.go (ply).kind,    "SandboxGoToSite", "no base, a site")
	T.eq (build.config.go (ply).kind,     "SandboxGoToSite", "no base, a site")
end)

T.test ("sandbox_builder is a sandbox player on the build mission", function ()
	local ply = Made (true, "sandbox_builder")
	T.eq (ply:ChooseMission (), "build", "its profile's")
	T.defined (ply.SandboxDefaults.BuildInterval, "the rest its base's")
end)

T.test ("it claims open ground its base fits, plans the base there and walks to it", function ()
	local ply, world = Made ()
	world.draws = { 2, 1 }
	T.eq (ply:ClaimSite (),  true, "claimed")
	T.eq (world.width,       nextsoldier.player.sandbox.blockout.Footprint (Sandbox.Spec (ply)), "as wide as its base")
	T.eq (world.planned [1], world.open [2], "walking to the second")
	T.eq (ply:Movement (),   "moving", "under way")
	local plan = nextsoldier.player.sandbox.blockout.Plan (world.open [2], 90, Sandbox.Spec (ply))
	T.eq (ply:BlockCount (), #plan, "planned, facing as drawn")
end)

T.test ("a site it cannot reach is given up; with none, it forgets those given up", function ()
	local ply, world = Made ()
	world.blocked [world.open [1]] = true
	T.eq (ply:ClaimSite (),  false, "no route to the first")
	T.eq (ply:BlockCount (), 0,     "no base")
	T.eq (ply:ClaimSite (),  true,  "the second")
	ply:ForgetSite ()
	T.eq (ply:BlockCount (), 0,     "given up")
	T.eq (ply:ClaimSite (),  false, "none left")
	world.blocked = {}
	T.eq (ply:ClaimSite (), true, "each again")
end)

T.test ("it places its base's blocks through its builder, and knows them standing", function ()
	local ply, world, _, builder = Made ()
	ply:ClaimSite ()
	T.eq (ply:BlockStanding (3),           false,                    "not yet")
	T.eq (ply:PlaceBlock (3),              true,                     "placed")
	T.eq (builder.spawned [1].owner,       ply,                      "as its own")
	T.eq (builder.spawned [1].block.model, Sandbox.Spec (ply).model, "of its plan")
	T.eq (ply:BlockStanding (3),           true,                     "standing")
	builder.gone [1] = true
	T.eq (ply:BlockStanding (3), false, "knocked down")
end)

T.test ("with no base, it has no blocks and places none", function ()
	local ply = Made ()
	T.eq (ply:BlockCount (),     0,     "none")
	T.eq (ply:PlaceBlock (1),    false, "nothing to place")
	T.eq (ply:BlockStanding (1), false, "nothing standing")
end)

T.test ("holding its base, it stands still looking out of its doorway", function ()
	local ply, world = Made ()
	world.draws = { 1, 0 }
	ply:ClaimSite ()
	ply:HoldBase ()
	local door = nextsoldier.player.sandbox.blockout.Door (world.open [1], 0, Sandbox.Spec (ply))
	local aim = ply.state.body.aim
	T.eq (ply:Movement (), "idle",                      "still")
	T.eq (aim.at.x,        door.x,                      "looking out of its doorway")
	T.eq (aim.at.y,        door.y,                      "looking out of its doorway")
	T.eq (aim.at.z,        door.z + Sandbox.EYE_HEIGHT, "eye-high")
	T.eq (aim.priority,    0,                           "a boring aim, anything else first")
	T.eq (aim.expires,     10 + Sandbox.HOLD_LOOK,      "for a while")
end)

T.test ("the builder it uses is held to its port", function ()
	Raises (function () Sandbox.InstallBuilder ({ Spawn = function () end }) end, "Standing")
end)

T.finish ()
