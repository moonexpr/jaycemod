-- team_train_watcher, loaded as GMod loads it but with nothing of Wetsands in
-- reach (a global it does not know is an error): it stands on Sandcastle's
-- modules and hooks alone, and its cart is moved by hand, driven (GMod's
-- drive system, drive_cart) or held by the physgun, only along its track.
local T = dofile ("tests/harness.lua")

local DIR = "addons/sandcastle/gamemodes/sandcastle/entities/entities/team_train_watcher/"
dofile ("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/cart_hud.lua")
local CART_HUD = package.loaded.cart_hud
local RED, BLUE, NOBODY = 2, 3, 0
local ROUND_ACTIVE = 2
local IN_ATTACK = 1

-- A fake world ---------------------------------------------------------------------

local VECTOR = {}
VECTOR.__index = VECTOR
local function Vector (x, y, z) return setmetatable ({ x = x, y = y, z = z }, VECTOR) end
VECTOR.__add = function (a, b) return Vector (a.x + b.x, a.y + b.y, a.z + b.z) end
VECTOR.__sub = function (a, b) return Vector (a.x - b.x, a.y - b.y, a.z - b.z) end
VECTOR.__mul = function (a, n) return Vector (a.x * n, a.y * n, a.z * n) end
function VECTOR:Dot (b) return self.x * b.x + self.y * b.y + self.z * b.z end
function VECTOR:LengthSqr () return self:Dot (self) end
function VECTOR:DistToSqr (b) return (self - b):LengthSqr () end
function VECTOR:Distance (b) return math.sqrt (self:DistToSqr (b)) end

local NULL = { IsValid = function () return false end }
local function IsValid (ent) return ent ~= nil and ent.IsValid ~= nil and ent:IsValid () end

local ENTITY = {}
ENTITY.__index = ENTITY
function ENTITY:IsValid () return true end
function ENTITY:GetClass () return self.class end
function ENTITY:GetName () return self.name end
function ENTITY:SetName (name) self.name = name end
function ENTITY:EntIndex () return self.index end
function ENTITY:GetPos () return self.pos end
function ENTITY:GetKeyValues () return self.kv end
function ENTITY:GetSpawnFlags () return self.flags end
function ENTITY:HasSpawnFlags (flag) return self.flags % (flag * 2) >= flag end
function ENTITY:GetInternalVariable (name) return self.vars [name] end
function ENTITY:SetKeyValue (key, value) self.kv [key] = value end
function ENTITY:GetParent () return self.parent or NULL end
function ENTITY:GetChildren () return self.children end
function ENTITY:SetNW2Bool (key, value) self.nw [key] = value end
function ENTITY:GetNW2Bool (key, default) return self.nw [key] == nil and default or self.nw [key] end
function ENTITY:Fire (input, value) self.fired [#self.fired + 1] = input .. " " .. tostring (value or "") end
function ENTITY:TriggerOutput (name, _, value)
	self.fired [#self.fired + 1] = "output " .. name .. " " .. tostring (value or "")
end
function ENTITY:StoreOutput () end
function ENTITY:NextThink (at) self.nextThink = at end
function ENTITY:IsBlocked () return false end

local World

local function Entity (class, name, fields)
	local ent = setmetatable (
		{
			class = class, name = name, index = #World.ents + 1, pos = Vector (0, 0, 0), kv = {}, flags = 0, vars = {},
			children = {}, nw = {}, fired = {}
		}, ENTITY)
	for key, value in pairs (fields or {}) do ent [key] = value end
	World.ents [#World.ents + 1] = ent
	return ent
end

-- The last thing fired at ent, or nil.
local function Last (ent) return ent.fired [#ent.fired] end

local PLAYER = setmetatable ({}, { __index = ENTITY })
PLAYER.__index = PLAYER
function PLAYER:IsAdmin () return self.admin end
function PLAYER:Alive () return true end
function PLAYER:KeyDown (key) return self.keys [key] == true end
function PLAYER:GetActiveWeapon () return self.weapon end
function PLAYER:GetShootPos () return self.pos end
function PLAYER:GetAimVector () return self.aim end
function PLAYER:GetDrivingEntity () return self.driving or NULL end

local function Player (fields)
	local ply = setmetatable ({ class = "player", keys = {}, weapon = NULL, admin = false }, PLAYER)
	ply.pos, ply.aim = Vector (0, 0, 0), Vector (1, 0, 0)
	for key, value in pairs (fields or {}) do ply [key] = value end
	return ply
end

-- A world with a straight track of three nodes along x, 500 apart, a train at
-- its start with a prop riding it, and the globals the watcher reads.
local function NewWorld (options)
	World = { ents = {}, now = 10, hooks = {}, controllers = {}, gameplay = false, rules = {}, adjusted = {}, events = {} }
	local env = {}
	env.ENT = {}
	env.NULL, env.IsValid, env.Vector = NULL, IsValid, Vector
	env.TEAM_RED, env.TEAM_BLUE, env.TF_TEAM_UNASSIGNED = RED, BLUE, NOBODY
	env.ROUND_ACTIVE, env.IN_ATTACK = ROUND_ACTIVE, IN_ATTACK
	env.TRANSMIT_NEVER = 0
	env.string, env.table, env.bit = string, table, bit
	-- GMod's math.Clamp
	local function Clamp (value, low, high) return math.min (math.max (value, low), high) end
	env.math = setmetatable ({ Clamp = Clamp }, { __index = math })
	env.ipairs, env.pairs, env.tonumber, env.tostring = ipairs, pairs, tonumber, tostring
	env.setmetatable, env.type = setmetatable, type
	env.include = function (file) return setfenv (assert (loadfile (DIR .. file)), env) () end
	env.CurTime = function () return World.now end
	env.CreateConVar = function (_, default) return { GetFloat = function () return tonumber (default) end } end
	env.timer = { Simple = function () end }
	env.ents =
	{
		FindByName = function (name)
			local found = {}
			for _, ent in ipairs (World.ents) do
				if ent.name == name then found [#found + 1] = ent end
			end
			return found
		end,
		FindByClass = function (class)
			local found = {}
			for _, ent in ipairs (World.ents) do
				if ent.class == class then found [#found + 1] = ent end
			end
			return found
		end
	}
	env.hook =
	{
		Add = function (name, id, fn)
			World.hooks [name] = World.hooks [name] or {}
			World.hooks [name] [id] = fn
		end,
		Run = function (name, ...)
			if name == "CartEvent" then World.events [#World.events + 1] = (select (2, ...)).kind end
			local answer = World.answers and World.answers [name]
			if answer then return answer (...) end
		end
	}
	env.game_manager =
	{
		Enable = function (name) World.enabled = name end,
		GetCurrentScenario = function () return { GetRules = function () return World.rules end } end
	}
	env.round_manager = { AdjustTime = function (info) World.adjusted [#World.adjusted + 1] = info end }
	-- the cart HUD's model, the gamemode's own module, as the watcher publishes by it
	env.cart_hud = CART_HUD
	-- what it networks to the HUD, kept by name
	World.globals = {}
	local function SetGlobal (name, value) World.globals [name] = value end
	env.SetGlobal2Bool, env.SetGlobal2Float, env.SetGlobal2Int, env.SetGlobal2String = SetGlobal, SetGlobal, SetGlobal, SetGlobal
	env.GAMEMODE =
	{
		AddController = function (_, controller) World.controllers [#World.controllers + 1] = controller end,
		IsGameplay = function () return World.gameplay end
	}
	-- a global the watcher does not know is an error: WS above all
	setmetatable (env, { __index = function (_, key) error ("the watcher read the global " .. tostring (key), 2) end })
	setfenv (assert (loadfile (DIR .. "init.lua")), env) ()

	local nodes = {}
	for i = 1, 3 do
		local target = i < 3 and "node" .. (i + 1) or ""
		nodes [i] = Entity ("path_track", "node" .. i, { pos = Vector ((i - 1) * 500, 0, 0), kv = { target = target } })
	end
	local train = Entity ("func_tracktrain", "train", { pos = Vector (0, 0, 0), vars = { m_flSpeed = 0, m_maxSpeed = 90 } })
	local prop = Entity ("prop_dynamic", "cart_prop", { parent = train })
	train.children = { prop }
	local watcher = Entity ("team_train_watcher", "watcher")
	setmetatable (watcher, { __index = function (_, key) return env.ENT [key] or ENTITY [key] end })
	watcher:KeyValue ("train",                 "train")
	watcher:KeyValue ("start_node",            "node1")
	watcher:KeyValue ("goal_node",             "node3")
	watcher:KeyValue ("handle_train_movement", options and options.mapDriven and "0" or "1")
	watcher:Initialize ()
	watcher:Think ()
	return watcher, train, prop
end

local function Think (watcher, seconds)
	World.now = World.now + (seconds or 0.1)
	watcher:Think ()
end

-- On its own ---------------------------------------------------------------------------

T.test ("the watcher loads and runs on Sandcastle alone, as the gamemode's cart controller", function ()
	local watcher, train = NewWorld ()
	T.eq (#World.controllers,         1,       "one controller")
	T.eq (World.controllers [1].type, "cart",  "a cart")
	T.eq (World.controllers [1].ent,  watcher, "itself")
	T.eq (watcher:IsActive (),        true,    "active")
	T.eq (#watcher:PathNodes (),      3,       "its path, by the nodes' own targets")
	T.eq (watcher:Train (),           train,   "its train")
end)

T.test ("a round becoming active activates it again", function ()
	local watcher = NewWorld ()
	watcher.activated = false
	World.hooks.OnRoundStateChanged [watcher] (watcher, ROUND_ACTIVE)
	T.eq (watcher.activated, true)
end)

T.test ("a scenario that says the cart is not running refuses an admin's moves; saying nothing, it runs", function ()
	local watcher = NewWorld ()
	World.rules = { CartRunning = false }
	local ok, why = watcher:AdvanceToNextCheckpoint ()
	T.eq (ok,  false)
	T.eq (why, "the round is not running")
	World.rules = {}
	_, why = watcher:AdvanceToNextCheckpoint ()
	T.eq (why, "no checkpoint ahead", "running: refused only for want of a checkpoint")
end)

T.test ("the scenario's speed scale is the train's top speed", function ()
	local watcher, train = NewWorld ()
	T.eq (train.kv.startspeed, "90", "the map's, unasked")
	World.rules = { CartSpeedScale = 2 }
	watcher:ApplyMaxSpeed ()
	T.eq (train.kv.startspeed, "180", "doubled")
end)

-- Driven --------------------------------------------------------------------------------

T.test ("the train and what rides it offer themselves to a hand", function ()
	local _, train, prop = NewWorld ()
	for _, body in ipairs ({ train, prop }) do
		T.eq (body:GetNW2Bool ("CartDrivable", false), true,         body.class .. " is drivable")
		T.eq (body:GetEntityDriveMode (),              "drive_cart", body.class .. " names the cart's drive mode")
	end
end)

T.test ("a driver's keys move the train along its track, and letting go gives it back", function ()
	local watcher, train = NewWorld ()
	local ply = Player ({ driving = train })
	T.eq (watcher:Drive (ply, train), true, "taken")
	T.eq (watcher:DriveKeys (ply, true, false), true)
	T.eq (Last (train), "SetSpeedDirAccel 1", "forward")
	watcher:DriveKeys (ply, false, true)
	T.eq (Last (train), "SetSpeedDirAccel -1", "back")
	watcher:DriveKeys (ply, false, false)
	T.eq (Last (train), "SetSpeedDirAccel 0", "standing")
	watcher:DriveKeys (ply, true, false)
	watcher:StopDriving (ply)
	T.eq (watcher:InHand (),                    false,                "let go")
	T.eq (Last (train),                         "SetSpeedDirAccel 0", "unpushed, it stands")
	T.eq (watcher:DriveKeys (ply, true, false), false,                "its keys no longer reach the cart")
end)

T.test ("a drive that ended some other way lets the cart go", function ()
	local watcher, train = NewWorld ()
	local ply = Player ({ driving = train })
	watcher:Drive (ply, train)
	watcher:DriveKeys (ply, true, false)
	ply.driving = nil
	Think (watcher)
	T.eq (watcher:InHand (), false)
	T.eq (Last (train),      "SetSpeedDirAccel 0")
end)

T.test ("one hand at a time", function ()
	local watcher, train = NewWorld ()
	local first, second = Player ({ driving = train }), Player ({ driving = train })
	T.eq (watcher:Drive (first, train), true)
	T.eq (watcher:Drive (second, train), false, "already in hand")
end)

T.test ("in sandbox anyone moves the cart; in a round only an admin; the gamemode's answer over both", function ()
	local watcher = NewWorld ()
	local ply, admin = Player (), Player ({ admin = true })
	T.eq (watcher:MayBeMovedBy (ply), true, "sandbox")
	World.gameplay = true
	T.eq (watcher:MayBeMovedBy (ply),   false, "a round, a player")
	T.eq (watcher:MayBeMovedBy (admin), true,  "a round, an admin")
	World.answers = { CartMayBeMoved = function () return false end }
	T.eq (watcher:MayBeMovedBy (admin), false, "the gamemode refuses")
	World.gameplay = false
	World.answers = { CartMayBeMoved = function () return true end }
	T.eq (watcher:MayBeMovedBy (ply), true, "the gamemode allows")
	World.answers = nil
	watcher:AcceptInput ("Disable")
	T.eq (watcher:MayBeMovedBy (ply), false, "a disabled watcher's cart is nobody's")
end)

T.test ("a cart whose watcher found no track is nobody's to move", function ()
	local watcher = NewWorld ()
	watcher:KeyValue ("start_node", "no_such_node")
	watcher:AcceptInput ("Enable")
	T.eq (#watcher:PathNodes (), 0, "no track")
	T.eq (watcher:MayBeMovedBy (Player ()), false)
end)

T.test ("a hand moves a cart the map drives itself, and gives it back to the map", function ()
	local watcher, train = NewWorld ({ mapDriven = true })
	local area = Entity ("trigger_capture_area", "area", { parent = train })
	local ply = Player ({ driving = train })
	watcher:Drive (ply, train)
	watcher:DriveKeys (ply, true, false)
	T.eq (Last (train), "SetSpeedDirAccel 1", "the watcher drives it while in hand")
	watcher:StopDriving (ply)
	T.eq (Last (train), "SetSpeedDirAccel 0",           "stopped")
	T.eq (Last (area),  "output OnNumCappersChanged 0", "and the map told its cappers again")
end)

T.test ("a cart in hand does not recede", function ()
	local watcher, train = NewWorld ()
	local ply = Player ({ driving = train })
	watcher:Drive (ply, train)
	watcher:InternalSetNumTrainCappers (0)
	Think (watcher, 60)
	T.eq (watcher.receding, false, "held past its recede time")
end)

-- Held by the physgun --------------------------------------------------------------------

local function Physgun () return Entity ("weapon_physgun", "") end

T.test ("the physgun does not lift the cart: it takes it in hand, and the cart follows the hold along its track", function ()
	local watcher, train, prop = NewWorld ()
	-- standing beside the track, holding the cart 200 away, the beam pointing up the track
	local ply = Player ({ pos = Vector (0, -100, 0), keys = { [IN_ATTACK] = true }, weapon = Physgun () })
	T.eq (prop:PhysgunPickup (ply), false, "the cart's prop is not lifted")
	T.eq (watcher:InHand (),        true,  "but the cart is in hand")
	ply.aim = Vector (1, 0, 0)
	ply.pos = Vector (400, -100, 0)
	Think (watcher)
	T.eq (Last (train), "SetSpeedDirAccel 1", "held far up the track: forward, off the track's side ignored")
	train.pos = Vector (900, 0, 0)
	train.vars.m_flSpeed = 90
	watcher:AcceptInput ("PathPassed", train, World.ents [2])
	Think (watcher)
	T.eq (Last (train), "SetSpeedDirAccel -1", "past the hold: back")
end)

T.test ("the physgun's hold ends with its trigger, or its gun", function ()
	local watcher, train = NewWorld ()
	local ply = Player ({ pos = Vector (0, -100, 0), keys = { [IN_ATTACK] = true }, weapon = Physgun () })
	train:PhysgunPickup (ply)
	ply.keys [IN_ATTACK] = false
	Think (watcher)
	T.eq (watcher:InHand (), false, "trigger released")
	ply.keys [IN_ATTACK] = true
	train:PhysgunPickup (ply)
	ply.weapon = Entity ("weapon_crowbar", "")
	Think (watcher)
	T.eq (watcher:InHand (), false, "another weapon out")
end)

T.test ("the physgun is refused as a driver is", function ()
	local watcher, train = NewWorld ()
	World.gameplay = true
	local ply = Player ({ keys = { [IN_ATTACK] = true }, weapon = Physgun () })
	T.eq (train:PhysgunPickup (ply), false)
	T.eq (watcher:InHand (), false, "a player's physgun, in a round")
end)

-- What it tells the gamemode ---------------------------------------------------------------

T.test ("an admin's retract and advance are the gamemode's to announce, and a point given back adds time", function ()
	local watcher, train = NewWorld ()
	watcher.links = { { cp = Entity ("team_control_point", "cp1"), distance = 500, index = 2, alerted = false } }
	train.pos = Vector (600, 0, 0)
	watcher.pathIndex = 2
	Think (watcher)
	World.events = {}
	T.eq (watcher:RetractToCheckpoint (), true)
	T.eq (World.events [#World.events],   "retract")
	T.eq (#World.adjusted,          1,              "time added")
	T.eq (World.adjusted [1].event, "cart_retract", "for the retract")
	T.eq (World.adjusted [1].delta > 0, true)
end)

T.finish ()
