-- nextsoldier.player: the CLuaNextBotPlayer, a bot player (NextBotPlayer<CGMOD_Player>) run
-- by a Lua class as a CLuaNextBot is by its ENT, base_nextbot2's interface on a player: its
-- profile, its root in the engine's Behavior, its life; and what a player has besides: the
-- console commands it runs and the user command it is given. Its components (locomotion,
-- body, vision) answer the engine from Lua puppets (nextsoldier.engine.Puppet). Over fakes of
-- the engine and of the player.
local T = dofile ("tests/harness.lua")
local Player = nextsoldier.player
local Usercmd = nextsoldier.player.usercmd

local Vec
local VecMeta = {}
VecMeta.__index = VecMeta
function VecMeta:Length2D () return math.sqrt (self.x * self.x + self.y * self.y) end
Vec = function (x, y, z) return setmetatable ({ x = x, y = y, z = z }, VecMeta) end

-- A bot player as the engine makes one: the fields it is given live in its entity table.
local function FakePlayer (name)
	local ply = { said = {}, selected = {}, health = 0, alive = true, onGround = true, crouching = false }
	function ply:GetTable () return self end
	function ply:Nick () return name end
	function ply:IsPlayer () return true end
	function ply:GetClass () return "player" end
	function ply:SetHealth (h) self.health = h end
	function ply:SetMaxHealth (h) self.maxHealth = h end
	function ply:Alive () return self.alive end
	function ply:GetPos () return Vec (0, 0, 0) end
	function ply:EyePos () return Vec (0, 0, 64) end
	function ply:EyeAngles () return { p = 0, y = 0, r = 0 } end
	function ply:IsOnGround () return self.onGround end
	function ply:Crouching () return self.crouching end
	function ply:GetVelocity () return Vec (3, 4, 0) end
	function ply:Say (text, team) self.said [#self.said + 1] = { text = text, team = team or false } end
	function ply:Kill () self.alive = false end
	function ply:SelectWeapon (class) self.selected [#self.selected + 1] = class end
	return ply
end

-- The engine as the binary publishes it, recording what it is asked.
local function FakeEngine ()
	local engine = { inserted = {}, puppeted = {}, ended = {} }
	function engine.Insert (bot, action, me) engine.inserted [#engine.inserted + 1] = { bot = bot, action = action, me = me } end
	function engine.End (bot) engine.ended [#engine.ended + 1] = bot end
	function engine.Stack () return {} end
	function engine.GroupStack () return {} end
	function engine.Puppet (bot, kind, puppet)
		engine.puppeted [kind] = { bot = bot, puppet = puppet }
		return {}
	end
	return engine
end

local function Services (engine, made)
	local services = { hooks = {}, ran = {}, now = 10 }
	function services.CreateBot (name)
		local ply = made or FakePlayer (name)
		return ply
	end
	services.Engine = engine
	function services.Now () return services.now end
	function services.Angle (p, y, r) return { p = p, y = y, r = r } end
	function services.RunConCommand (ply, name, args, argStr)
		services.ran [#services.ran + 1] = { ply = ply, name = name, args = args, argStr = argStr }
		return true
	end
	function services.AddHook (name, id, fn) services.hooks [name] = fn end
	return services
end

local function Made (class, fields)
	local engine = FakeEngine ()
	for k, v in pairs (fields or {}) do engine [k] = v end
	local services = Services (engine)
	Player.Install (services)
	local ply = Player.Create (class, "Bot")
	return ply, engine, services
end

-- A class's own behaviour, deriving from the base's root, as base_nextbot2's classes do.
local BaseRoot = action_registry.Get ("NextBotPlayer")
local TestRoot = action_registry.Register ("TestPlayerRoot", {}, "NextBotPlayer")
function TestRoot:OnStart (me)
	me.started = me.started + 1
	return self:Continue ()
end
function TestRoot:Update (me, interval)
	me.updated = me.updated + interval
	return BaseRoot.Update (self, me, interval)
end

Player.Register ("test_player",
	{
		Base = "base_nextbot_player",
		Behavior = "TestPlayerRoot",
		LocomotionDefaults = { RunSpeed = 300 },
		started = 0,
		updated = 0
	}
)
local TestClass = Player.Get ("test_player")
function TestClass:InitialAction () return { name = "TestFirst" } end

T.test ("the services are held to their port", function ()
	T.eq (pcall (Player.Install, {}), false, "a table lacking them is refused")
end)

T.test ("a class reads through to its base, its profile's tables too", function ()
	local class = Player.Get ("test_player")
	T.eq (class.LocomotionDefaults.RunSpeed,  300, "its own")
	T.eq (class.LocomotionDefaults.WalkSpeed, Player.Get ("base_nextbot_player").LocomotionDefaults.WalkSpeed, "its base's")
	T.eq (type (class.Initialize),            "function", "its base's methods")
end)

T.test ("a class is refused when its base is not one", function ()
	Player.Register ("test_orphan", { Base = "no_such_base" })
	T.eq (pcall (Player.Get, "test_orphan"),           false, "an unknown base")
	T.eq (pcall (Player.Get, "test_never_registered"), false, "an unknown class")
	Player.Register ("test_loop", { Base = "test_loop" })
	T.eq (pcall (Player.Get, "test_loop"), false, "its own base")
end)

T.test ("a bot of a class gets its root and its puppets, and its health is the game's", function ()
	local ply, engine = Made ("test_player")
	T.eq (Player.Of (ply),  "test_player", "it is one")
	T.eq (ply.health,       0,             "a regular player's: the gamemode spawns it")
	T.eq (#engine.inserted, 1,             "its root inserted")
	local root = engine.inserted [1]
	T.eq (root.bot,         ply,              "on it")
	T.eq (root.me,          ply,              "told it")
	T.eq (root.action.name, "TestPlayerRoot", "its class's behaviour")
	for _, kind in ipairs ({ "locomotion", "body", "vision" }) do
		T.eq (engine.puppeted [kind] and engine.puppeted [kind].bot, ply, kind .. " puppeted")
	end
	T.eq (engine.puppeted.locomotion.puppet, nextsoldier.player.puppets.Locomotion, "the base's locomotion")
end)

T.test ("each bot's profile is its own, read through to its class's", function ()
	local a = Made ("test_player")
	local b = Made ("test_player")
	a.LocomotionDefaults.RunSpeed = 50
	T.eq (a.LocomotionDefaults.RunSpeed,                          50,  "changed on one")
	T.eq (b.LocomotionDefaults.RunSpeed,                          300, "not the other's")
	T.eq (Player.Get ("test_player").LocomotionDefaults.RunSpeed, 300, "nor its class's")
end)

T.test ("with no binary, a bot is a plain bot player its class runs from Lua, saying why", function ()
	local services = Services ({ refused = "server.dll is not loaded" })
	Player.Install (services)
	local ply = Player.Create ("test_player", "Bot")
	T.eq (Player.Of (ply),                  "test_player",              "made")
	T.eq (ply.state.unbound,                "server.dll is not loaded", "why it runs unbound")
	T.eq (ply.state.puppets.refused ~= nil, true,                       "nothing puppeted")
	services.hooks.Think ()
	T.eq (ply.started, 1, "its Think starts it")
	T.eq (ply.updated, 0, "no time yet")
	services.now = services.now + 0.5
	services.hooks.Think ()
	T.eq (ply.started, 1, "once")
	T.near (ply.updated, 0.5, 1e-6, "updated by the time since")
	ply:RunCommand ("say unbound")
	T.eq (ply.said [1].text, "unbound", "its commands still run")
	services.hooks.EntityRemoved (ply)
	T.eq (Player.Of (ply), nil, "removed")
end)

T.test ("bound, its Think leaves its root to the engine", function ()
	local ply, _, services = Made ("test_player")
	services.hooks.Think ()
	services.now = services.now + 1
	services.hooks.Think ()
	T.eq (ply.started,       0,   "the engine starts it")
	T.eq (ply.updated,       0,   "the engine updates it")
	T.eq (ply.state.unbound, nil, "bound")
end)

T.test ("no slot for a bot makes none", function ()
	local services = Services (FakeEngine ())
	function services.CreateBot () return nil end
	Player.Install (services)
	T.eq (Player.Create ("test_player", "Bot"), nil, "none")
end)

T.test ("a kind the binary does not puppet is driven from Lua alone and says why; the rest are puppeted", function ()
	local why = "ILocomotion's slot order is not yet read from the binary"
	local ply, engine = Made ("test_player", { puppet_refused = { locomotion = why } })
	T.eq (engine.puppeted.locomotion,                            nil, "locomotion not puppeted")
	T.eq (ply.state.puppets.refused.locomotion,                  why, "why")
	T.eq (engine.puppeted.body and engine.puppeted.body.bot,     ply, "its body puppeted")
	T.eq (engine.puppeted.vision and engine.puppeted.vision.bot, ply, "its vision puppeted")
end)

T.test ("its root sets its pace each update: its run, held to its walk while its battery is spent", function ()
	local ply, engine = Made ("test_player")
	local root = engine.inserted [1].action
	root:Update (ply, 0.1)
	T.eq (ply.state.loco.pace,                                      300,  "its run")
	T.eq (ply:Battery ():Level (10) < ply.BatteryDefaults.Capacity, true, "a sprint is paid for")
	ply:SpendBattery (ply.BatteryDefaults.Capacity)
	T.eq (ply:IsExhausted (), true, "spent")
	root:Update (ply, 0.1)
	T.eq (ply.state.loco.pace,      ply.LocomotionDefaults.WalkSpeed,       "held to its walk")
	T.eq (root:ShouldRetreat (ply), nextsoldier.behavior.action.ANSWER_YES, "it would rather retreat")
	nextsoldier.player.puppets.Locomotion:Approach (ply, Vec (1000, 0, 0), 1)
	local cmd = {}
	local set = {}
	for _, name in ipairs ({ "ClearMovement", "ClearButtons", "SetButtons", "SetSideMove", "SetUpMove", "SetImpulse" }) do
		cmd [name] = function () end
	end
	function cmd:SetForwardMove (v) set.forward = v end
	function cmd:SetViewAngles () end
	ply:StartCommand (cmd)
	T.near (set.forward, ply.LocomotionDefaults.WalkSpeed, 1e-6, "its command at that pace")
end)

T.test ("its legs, when it names them, go in beside its behaviour", function ()
	Player.Register ("test_legged", { Base = "test_player", Legs = "TestPlayerRoot" })
	local grouped
	local ply = Made ("test_legged", { InsertGroup = function (bot, action, me) grouped = { bot = bot, action = action } end })
	T.eq (grouped and grouped.bot, ply,              "inserted on it")
	T.eq (grouped.action.name,     "TestPlayerRoot", "the legs it names")
end)

T.test ("its root starts the bot, updates it and contains its first action", function ()
	local ply, engine = Made ("test_player")
	local root = engine.inserted [1].action
	root:OnStart (ply)
	T.eq (ply.started, 1, "its behaviour started")
	root:Update (ply, 0.25)
	T.eq (ply.updated,                            0.25,        "updated, told the interval")
	T.eq (root:InitialContainedAction (ply).name, "TestFirst", "its first action")
end)

T.test ("a command the engine hands its root (nb_command) is a command it runs", function ()
	local ply, engine, services = Made ("test_player")
	engine.inserted [1].action:OnCommandString (ply, "say hi")
	T.eq (ply.said [1] and ply.said [1].text, "hi", "said")
end)

T.test ("its commands: its class first, then held keys, a player's own, then Lua's", function ()
	local ply, _, services = Made ("test_player")
	local heard
	function ply:OnCommand (name, args) if name == "taunt" then heard = args [1] return true end end
	ply:RunCommand ("taunt loud; +attack; say_team go; kill; use weapon_smg1; mycmd 1 2")
	T.eq (heard,                                        "loud", "its class's")
	T.eq (Usercmd.Has (ply.state.input.held, "attack"), true, "held")
	T.eq (ply.said [1].text,                            "go", "said")
	T.eq (ply.said [1].team,                            true, "to its team")
	T.eq (ply.alive,                                    false, "killed")
	T.eq (ply.selected [1],                             "weapon_smg1", "its weapon")
	T.eq (#services.ran,                                1, "only the one left over goes to Lua's console commands")
	T.eq (services.ran [1].name,                        "mycmd", "named")
	T.eq (services.ran [1].ply,                         ply, "as it")
	T.eq (services.ran [1].argStr,                      "1 2", "its argument string")
end)

-- The command it presses this tick, as StartCommand writes it.
local function Pressed (ply)
	local cmd, set = {}, {}
	function cmd:ClearMovement () end
	function cmd:ClearButtons () end
	function cmd:SetButtons (b) set.buttons = b end
	function cmd:SetForwardMove (v) set.forward = v end
	function cmd:SetSideMove (v) set.side = v end
	function cmd:SetUpMove (v) set.up = v end
	function cmd:SetImpulse (v) set.impulse = v end
	function cmd:SetViewAngles (a) set.angles = a end
	ply:StartCommand (cmd)
	return set
end

T.test ("sent somewhere through its locomotion, it runs at it, looking where it goes", function ()
	local ply = Made ("test_player")
	local Loco = nextsoldier.player.puppets.Locomotion
	T.eq (Loco:Approach (ply, Vec (0, 1000, 0), 1), true, "the engine's call handled")
	T.eq (Loco:IsAttemptingToMove (ply),            true, "moving")
	local set = Pressed (ply)
	T.near (set.angles.y, 90,                              1e-6, "faces its way")
	T.near (set.forward,  ply.LocomotionDefaults.RunSpeed, 1e-6, "runs ahead")
	T.near (set.side,     0,                               1e-6, "straight")
	Loco:Stop (ply)
	set = Pressed (ply)
	T.eq (set.forward, 0, "stopped")
end)

T.test ("it walks at a walk, and jumps once when asked", function ()
	local ply = Made ("test_player")
	local Loco = nextsoldier.player.puppets.Locomotion
	Loco:Walk (ply)
	T.eq (Loco:IsRunning (ply), false, "walking")
	Loco:Approach (ply, Vec (1000, 0, 0), 1)
	Loco:Jump (ply)
	local set = Pressed (ply)
	T.near (set.forward, ply.LocomotionDefaults.WalkSpeed, 1e-6, "at a walk")
	T.eq (Usercmd.Has (set.buttons, "jump"),           true,  "jumps")
	T.eq (Usercmd.Has (Pressed (ply).buttons, "jump"), false, "once")
end)

T.test ("its goal reached, it stands and is let go", function ()
	local ply = Made ("test_player")
	local Loco = nextsoldier.player.puppets.Locomotion
	Loco:Approach (ply, Vec (nextsoldier.player.base_nextbot_player.ARRIVE - 1, 0, 0), 1)
	local set = Pressed (ply)
	T.eq (set.forward,                   0,     "stands")
	T.eq (Loco:IsAttemptingToMove (ply), false, "let go")
end)

T.test ("turned by its locomotion, it looks level that way, this tick only", function ()
	local ply = Made ("test_player")
	nextsoldier.player.puppets.Locomotion:FaceTowards (ply, Vec (0, 1000, -500))
	local set = Pressed (ply)
	T.near (set.angles.y, 90, 1e-6, "that way")
	T.eq (set.angles.p,                                               0,     "level")
	T.eq (nextsoldier.player.puppets.Body:IsHeadAimingOnTarget (ply), false, "not an aim")
	T.eq (Pressed (ply).angles,                                       nil,   "once")
end)

T.test ("aimed at an entity, it looks at its centre", function ()
	local ply = Made ("test_player")
	local target = { WorldSpaceCenter = function () return Vec (-1000, 0, 64) end }
	nextsoldier.player.puppets.Body:AimHeadTowardsEntity (ply, target, 1, 1, "test")
	T.near (math.abs (Pressed (ply).angles.y), 180, 1e-6, "-x")
end)

T.test ("its head aims where its body is told, over where it goes", function ()
	local ply = Made ("test_player")
	local Body = nextsoldier.player.puppets.Body
	nextsoldier.player.puppets.Locomotion:Approach (ply, Vec (1000, 0, 0), 1)
	T.eq (Body:AimHeadTowards (ply, Vec (0, -1000, 64), 1, 1, "test"), true, "handled")
	local set = Pressed (ply)
	T.near (set.angles.y, -90,                              1e-6, "looks at it")
	T.near (set.side,     -ply.LocomotionDefaults.RunSpeed, 1e-6, "still goes east: to its left")
	T.eq (Body:IsHeadAimingOnTarget (ply), true, "on target")
end)

T.test ("an aim lasts its duration; a lower priority does not take it before", function ()
	local ply, _, services = Made ("test_player")
	local Body = nextsoldier.player.puppets.Body
	Body:AimHeadTowards (ply, Vec (0, 1000, 64),  2, 1, "important")
	Body:AimHeadTowards (ply, Vec (0, -1000, 64), 1, 1, "boring")
	T.near (Pressed (ply).angles.y, 90, 1e-6, "the important one")
	services.now = services.now + 2
	T.eq (Pressed (ply).angles, nil, "over: its eyes are its own")
end)

T.test ("crouched by its body's posture, it ducks", function ()
	local ply = Made ("test_player")
	local Body = nextsoldier.player.puppets.Body
	Body:SetDesiredPosture (ply, Body.CROUCH)
	T.eq (Body:GetDesiredPosture (ply),                Body.CROUCH, "desired")
	T.eq (Usercmd.Has (Pressed (ply).buttons, "duck"), true,        "ducks")
	ply.crouching = true
	T.eq (Body:GetActualPosture (ply), Body.CROUCH, "crouched")
end)

T.test ("a user command given replaces what it would press, once, held keys and all", function ()
	local ply = Made ("test_player")
	ply:RunCommand ("+duck; impulse 100")
	ply:SetUserCmd ({ forward = 7, buttons = { "attack" }, pitch = 1, yaw = 2, weapon = "weapon_ar2" })
	local set = Pressed (ply)
	T.eq (set.forward,                         7,            "its move")
	T.eq (Usercmd.Has (set.buttons, "attack"), true,         "its buttons")
	T.eq (Usercmd.Has (set.buttons, "duck"),   true,         "and those held")
	T.eq (set.impulse,                         100,          "the impulse asked")
	T.eq (set.angles.y,                        2,            "its eyes")
	T.eq (ply.selected [1],                    "weapon_ar2", "its weapon")
	set = Pressed (ply)
	T.eq (set.forward,                       0,    "once")
	T.eq (set.impulse,                       0,    "the impulse once")
	T.eq (Usercmd.Has (set.buttons, "duck"), true, "held still")
end)

T.test ("a class has the last word on its command", function ()
	local ply = Made ("test_player")
	function ply:OnUserCmd (cmd) return Usercmd.With (cmd, Usercmd.Buttons ({ "reload" })) end
	T.eq (Usercmd.Has (Pressed (ply).buttons, "reload"), true, "its own")
end)

T.test ("a user command that is not one is refused as it is given", function ()
	local ply = Made ("test_player")
	T.eq (pcall (ply.SetUserCmd, ply, { forwrad = 1 }), false, "refused")
end)

T.test ("its puppets answer the engine from its profile", function ()
	local ply = Made ("test_player")
	local Puppets = nextsoldier.player.puppets
	T.eq (Puppets.Locomotion:GetRunSpeed (ply),   300,                               "run")
	T.eq (Puppets.Locomotion:GetWalkSpeed (ply),  ply.LocomotionDefaults.WalkSpeed,  "walk")
	T.eq (Puppets.Locomotion:GetStepHeight (ply), ply.LocomotionDefaults.StepHeight, "step")
	T.eq (Puppets.Locomotion:IsOnGround (ply),    true,                              "on the ground")
	T.near (Puppets.Locomotion:GetSpeed (ply), 5, 1e-6, "its speed across the ground")
	T.eq (Puppets.Locomotion:SetDesiredSpeed (ply, 42), true,                           "handled")
	T.eq (Puppets.Locomotion:GetDesiredSpeed (ply),     42,                             "kept")
	T.eq (Puppets.Body:GetHullHeight (ply),             ply.BodyDefaults.HullHeight,    "hull")
	T.eq (Puppets.Vision:GetFieldOfView (ply),          ply.VisionDefaults.FieldOfView, "its default view")
	Puppets.Vision:SetFieldOfView (ply, 45)
	T.eq (Puppets.Vision:GetFieldOfView (ply),        45,                                "narrowed")
	T.eq (Puppets.Vision:GetDefaultFieldOfView (ply), ply.VisionDefaults.FieldOfView,    "its default kept")
	T.eq (Puppets.Vision:GetMaxVisionRange (ply),     ply.VisionDefaults.MaxVisionRange, "range")
end)

T.test ("the game's hooks reach its bots, and only them", function ()
	local ply, engine, services = Made ("test_player")
	local hooks = services.hooks
	for _, name in ipairs ({ "StartCommand", "PlayerSpawn", "EntityTakeDamage", "DoPlayerDeath", "Think", "EntityRemoved" }) do
		T.eq (type (hooks [name]), "function", name)
	end
	local other = FakePlayer ("human")
	T.eq (pcall (hooks.EntityTakeDamage, other, {}), true, "another player is let be")

	local hurt, died, thought
	function ply:OnInjured (dmg) hurt = dmg end
	function ply:OnDeath (dmg) died = dmg end
	function ply:Think () thought = true end
	local dmg = { GetAttacker = function () return other end }
	hooks.EntityTakeDamage (ply, dmg)
	T.eq (hurt, dmg, "hurt")
	hooks.Think ()
	T.eq (thought, true, "thinks")
	hooks.DoPlayerDeath (ply, other, dmg)
	T.eq (died,                 dmg,   "its death")
	T.eq (ply:IsAlive (),       true,  "its life is the player's")
	T.eq (ply.state.life.alive, false, "this life over")
	hooks.PlayerSpawn (ply)
	T.eq (ply.state.life.alive, true, "a new life")
	hooks.EntityRemoved (ply)
	T.eq (engine.ended [1], ply, "its actions ended")
	T.eq (Player.Of (ply),  nil, "forgotten")
end)

T.test ("its default hooks are base_nextbot2's", function ()
	local base = Player.Get ("base_nextbot_player")
	for _, name in ipairs ({ "SetupProfile", "OnProfile", "RootAction", "InitialAction", "Reset", "IsAlive", "IsDead",
		"OnInjured", "OnKilled", "OnDeath", "OnRemove", "BehaveStart", "BehaveUpdate", "CalcDesiredSpeed", "Think",
		"BodyUpdate", "DebugStack", "DebugWatch", "DebugBehaviorChanged", "LegsAction", "Battery", "IsExhausted",
		"SpendBattery", "RewardBattery", "OnNewEnemy", "OnEnemyChange", "OnLastEnemy", "OnFetchEnemy",
		"OnSpotted", "OnLost", "OnComputePath", "OnUpdateAnimation" }) do
			T.eq (type (base [name]), "function", name)
		end
end)

T.finish ()
