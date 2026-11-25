-- nextsoldier.behavior.cscanner: HL2's city scanner (npc_scanner.cpp, npc_basescanner.cpp) as a
-- family of actions (nextbot_cscanner's). The family's responders are three questions,
-- ShouldEvacuate, ShouldAttack and ShouldFollow, which every scanner action answers for itself;
-- its monitor asks them of what it runs and suspends for the most urgent, each action keeping on
-- while its own answer holds.
local T = dofile ("tests/harness.lua")
local Action = nextsoldier.behavior.action
local Scanner = nextsoldier.behavior.cscanner
local Registry = action_registry
local Geometry = math.geometry
local StateChart = generator.state_chart

for _, name in ipairs ({ "PATROL_REACH", "PATROL_REST", "FOLLOW_DISTANCE", "FOLLOW_LOSE", "PHOTO_NEAR", "PHOTO_FAR",
	"PHOTO_MIN_DELAY", "PHOTO_MAX_DELAY", "INSPECT_LENGTH", "INSPECT_DELAY", "ATTACK_DISTANCE", "ATTACK_RANGE",
	"ATTACK_MIN_DELAY", "ATTACK_MAX_DELAY", "EVACUATE_HEALTH", "HURT_WINDOW", "EVACUATE_DISTANCE", "EVACUATE_SECONDS" }) do
		T.defined (Scanner [name], name)
	end

-- HL2's own, from npc_scanner.cpp and npc_basescanner.h.
T.test ("its distances and times are HL2's", function ()
	T.eq (Scanner.FOLLOW_DISTANCE, 96, "between SCANNER_PHOTO_NEAR_DIST and _FAR_DIST")
	T.eq (Scanner.PHOTO_NEAR, 64)
	T.eq (Scanner.PHOTO_FAR,  128)
	T.eq (Scanner.PHOTO_MIN_DELAY, 5, "TASK_CSCANNER_PHOTOGRAPH's SetWait (5, 10)")
	T.eq (Scanner.PHOTO_MAX_DELAY, 10)
	T.eq (Scanner.INSPECT_LENGTH,   5,    "SCANNER_CIT_INSPECT_LENGTH")
	T.eq (Scanner.INSPECT_DELAY,    10,   "SCANNER_CIT_INSPECT_DELAY")
	T.eq (Scanner.FOLLOW_LOSE,      1500, "SCANNER_CIT_INSPECT_FLY_DIST")
	T.eq (Scanner.ATTACK_DISTANCE,  225,  "between SCANNER_ATTACK_NEAR_DIST and _FAR_DIST")
	T.eq (Scanner.ATTACK_RANGE,     350,  "SCANNER_ATTACK_RANGE")
	T.eq (Scanner.ATTACK_MIN_DELAY, 8,    "SCANNER_ATTACK_MIN_DELAY")
	T.eq (Scanner.ATTACK_MAX_DELAY, 12,   "SCANNER_ATTACK_MAX_DELAY")
	T.eq (Scanner.EVACUATE_HEALTH,  0.75, "3 * sk_scanner_health / 4")
	T.eq (Scanner.HURT_WINDOW,      1,    "SCANNER_EVADE_TIME")
end)

local YES, NO = Action.ANSWER_YES, Action.ANSWER_NO

-- A scanner as its actions see it: where it is, its health and clock, its draws (0 to 1), who it
-- inspects and who it fights (each a handle and where it is), when it was last hurt and from
-- where, the spots it patrols; what it was told to fly to, whom it photographed and whom it
-- flashed are the test's to read. Ask goes to the machine running it, as a bot's intention would.
local function Fake ()
	local me = { pos = { x = 0, y = 0, z = 0 }, health = 40, maxHealth = 40, now = 0, draw = 0.5, spots = {},
		flown = nil, hovering = false, photos = {}, flashes = {} }
	function me:Now () return self.now end
	function me:Random () return self.draw end
	function me:Health () return self.health end
	function me:MaxHealth () return self.maxHealth end
	function me:Position () return self.pos end
	function me:Target () return self.target end
	function me:TargetPosition () return self.targetPos end
	function me:Enemy () return self.enemy end
	function me:EnemyPosition () return self.enemyPos end
	function me:HurtSince (t) return self.hurtAt ~= nil and self.hurtAt > t end
	function me:HurtFrom () return self.hurtFrom end
	function me:PatrolSpot () return table.remove (self.spots, 1) end
	function me:FlyTo (p) self.flown, self.hovering = p, false end
	function me:Hover () self.flown, self.hovering = nil, true end
	function me:Photograph (who) self.photos [#self.photos + 1] = { who = who, at = self.now } end
	function me:Flash (who) self.flashes [#self.flashes + 1] = { who = who, at = self.now } end
	function me:Ask (name) return self.machine:Query (self, name) end
	return me
end

-- A scanner running its monitor, updated at its clock.
local function Running ()
	local me = Fake ()
	me.machine = StateChart.Behavior:New (Scanner.ScannerMonitor:New ())
	function me:Tick (seconds)
		self.now = self.now + (seconds or 0.1)
		self.machine:Update (self, seconds or 0.1)
	end
	function me:Doing ()
		local frames = self.machine:Stack ()
		for i = #frames, 1, -1 do
			if not frames [i].suspended then return frames [i].name end
		end
	end
	return me
end

-- What a draw of 0.5 makes of a range.
local function Middle (low, high) return low + 0.5 * (high - low) end

T.test ("the fake is the port its actions are written against", function ()
	T.eq (Scanner.PORT:Check (Fake ()) ~= nil, true)
end)

T.test ("every scanner action answers the family's three questions itself", function ()
	for _, name in ipairs ({ "ScannerPatrol", "ScannerFollow", "ScannerAttack", "ScannerEvacuate" }) do
		T.eq (Registry.BaseOf (name), "Scanner", name .. " is a scanner action")
		local class = Registry.Get (name)
		for _, query in ipairs ({ "ShouldFollow", "ShouldEvacuate", "ShouldAttack" }) do
			T.eq (type (rawget (class, query)), "function", name .. " answers " .. query .. " itself")
		end
	end
	T.eq (Registry.Unanswered ().ScannerPatrol, nil)
	Registry.Register ("ScannerDrift", {}, "Scanner")
	local ok, why = pcall (Registry.New, "ScannerDrift")
	T.eq (ok, false, "a scanner action with no answers is refused")
	T.eq (tostring (why):find ("ScannerDrift does not answer ShouldAttack, ShouldEvacuate, ShouldFollow (Scanner's)",
		1, true) ~= nil, true, tostring (why))
end)

T.test ("alone, it patrols its spots, resting at each", function ()
	local me = Running ()
	me.spots = { { x = 500, y = 0, z = 0 }, { x = 0, y = 500, z = 0 } }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerPatrol")
	T.eq (me.flown.x, 500, "off to its first spot")
	me.pos = { x = 500, y = 0, z = 0 }
	me:Tick ()
	T.eq (me.hovering, true, "arrived: it rests")
	me:Tick (Scanner.PATROL_REST)
	me:Tick ()
	T.eq (me.flown.y, 500, "rested: the next spot")
end)

-- Into its photograph range: 2D, strictly between PHOTO_NEAR and PHOTO_FAR.
local function Inspected (me)
	me.pos = { x = me.targetPos.x - Scanner.FOLLOW_DISTANCE, y = 0, z = 0 }
end

T.test ("one it sees it inspects: it holds off, photographs them in range, and again after a wait", function ()
	local me = Running ()
	me:Tick ()
	me.target, me.targetPos = "citizen", { x = 1000, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerFollow")
	T.near (Geometry.Distance2D (me.flown, me.targetPos), Scanner.FOLLOW_DISTANCE, 0.01, "holds off")
	T.eq (#me.photos, 0, "out of range: no photograph")
	me:Tick (Scanner.INSPECT_LENGTH + 1)
	T.eq (me:Doing (), "ScannerFollow", "its inspection only counts from when it arrives")
	Inspected (me)
	me:Tick ()
	T.eq (#me.photos, 1, "in range: a photograph")
	T.eq (me.photos [1].who, "citizen")
	T.eq (#me.flashes, 0, "a photograph, not an attack's flash")
	me:Tick ()
	T.eq (#me.photos, 1, "not again so soon")
end)

T.test ("too near, it photographs no one until it has backed off", function ()
	local me = Running ()
	me:Tick ()
	me.target, me.targetPos = "citizen", { x = 300, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	me.pos = { x = me.targetPos.x - Scanner.PHOTO_NEAR, y = 0, z = 0 }
	me:Tick ()
	T.eq (#me.photos, 0, "at PHOTO_NEAR: too near")
	Inspected (me)
	me:Tick ()
	T.eq (#me.photos, 1)
end)

T.test ("its inspection over, it lets them be until it looks again", function ()
	local me = Running ()
	me:Tick ()
	me.target, me.targetPos = "citizen", { x = 300, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	Inspected (me)
	me:Tick ()
	T.eq (#me.photos, 1)
	me:Tick (Scanner.INSPECT_LENGTH)
	me:Tick ()
	T.eq (me:Doing (),             "ScannerPatrol", "inspected: back to its patrol")
	T.eq (me:Ask ("ShouldFollow"), NO,              "not again so soon")
	me:Tick (Scanner.INSPECT_DELAY)
	me:Tick ()
	T.eq (me:Doing (), "ScannerFollow", "its delay over: it inspects again")
end)

T.test ("one that moves off is followed, its inspection kept, and photographed again after a drawn wait", function ()
	local me = Running ()
	me:Tick ()
	me.target, me.targetPos = "citizen", { x = 300, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	Inspected (me)
	me.draw = 0
	me:Tick ()
	T.eq (#me.photos, 1)
	me.targetPos = { x = 800, y = 0, z = 0 }
	me:Tick (Scanner.PHOTO_MIN_DELAY - 0.5)
	T.eq (me:Doing (), "ScannerFollow", "following them, its inspection is not over")
	Inspected (me)
	me:Tick ()
	T.eq (#me.photos, 1, "its wait not over")
	me:Tick (0.6)
	T.eq (#me.photos, 2, "PHOTO_MIN_DELAY on a draw of 0")
end)

T.test ("one too far away is let go", function ()
	local me = Running ()
	me:Tick ()
	me.target, me.targetPos = "citizen", { x = 200, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerFollow")
	me.targetPos = { x = Scanner.FOLLOW_LOSE + 1, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerPatrol")
end)

T.test ("an enemy it attacks, over anyone it inspects, flashing it in range on a drawn delay", function ()
	local me = Running ()
	me:Tick ()
	me.target, me.targetPos = "citizen", { x = 200, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	me.enemy, me.enemyPos = "player", { x = 0, y = 600, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerAttack", "attacking comes first")
	T.near (Geometry.Distance2D (me.flown, me.enemyPos), Scanner.ATTACK_DISTANCE, 0.01, "holds off")
	T.eq (#me.flashes, 0, "out of range")
	me.pos = { x = 0, y = 600 - Scanner.ATTACK_RANGE, z = 0 }
	me:Tick ()
	T.eq (#me.flashes, 1, "at its range: a flash")
	T.eq (me.flashes [1].who, "player")
	local delay = Middle (Scanner.ATTACK_MIN_DELAY, Scanner.ATTACK_MAX_DELAY)
	me:Tick (delay - 0.5)
	T.eq (#me.flashes, 1, "not before its delay")
	me:Tick (0.6)
	T.eq (#me.flashes, 2)
	me.enemy, me.enemyPos = nil, nil
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerFollow", "its enemy gone: back to whom it inspected")
end)

T.test ("hurt badly fighting, it fights on: HL2's scanner takes cover only when alert", function ()
	local me = Running ()
	me:Tick ()
	me.enemy, me.enemyPos = "player", { x = 300, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	me.health, me.hurtAt, me.hurtFrom = 1, me.now, me.enemyPos
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (),               "ScannerAttack")
	T.eq (me:Ask ("ShouldEvacuate"), NO)
end)

T.test ("hurt with no enemy, below three quarters of its health, it takes cover away from the hurt, once", function ()
	local me = Running ()
	me:Tick ()
	me.health = me.maxHealth * Scanner.EVACUATE_HEALTH - 1
	me.hurtAt, me.hurtFrom = me.now, { x = 300, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerEvacuate")
	T.eq (me.flown.x < 0, true, "away from where it was hurt from")
	T.near (Geometry.Distance2D (me.flown, me.pos), Scanner.EVACUATE_DISTANCE, 0.01)
	me:Tick (Scanner.EVACUATE_SECONDS)
	me:Tick ()
	T.eq (me:Doing (), "ScannerPatrol", "covered, it patrols")
	me:Tick ()
	T.eq (me:Doing (), "ScannerPatrol", "not again for the same hurt")
	me.hurtAt = me.now
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerEvacuate", "hurt again")
end)

T.test ("hurt at three quarters of its health, it shrugs it off", function ()
	local me = Running ()
	me:Tick ()
	me.health = me.maxHealth * Scanner.EVACUATE_HEALTH
	me.hurtAt, me.hurtFrom = me.now, { x = 300, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerPatrol")
end)

T.test ("a hurt older than its window is no reason to take cover", function ()
	local me = Running ()
	me:Tick ()
	me.health, me.hurtAt, me.hurtFrom = 1, me.now, { x = 300, y = 0, z = 0 }
	me:Tick (Scanner.HURT_WINDOW + 0.1)
	T.eq (me:Ask ("ShouldEvacuate"), NO)
end)

T.test ("its answers, as the soldier's intention is asked them", function ()
	local me = Running ()
	me:Tick ()
	T.eq (me:Ask ("ShouldFollow"),   NO)
	T.eq (me:Ask ("ShouldAttack"),   NO)
	T.eq (me:Ask ("ShouldEvacuate"), NO)
	me.target, me.targetPos = "citizen", { x = 200, y = 0, z = 0 }
	T.eq (me:Ask ("ShouldFollow"), YES, "its patrol says so before it follows")
end)

-- The entity is GMod's, so no more of it runs here than its file's top level: what it defines.
T.test ("nextbot_cscanner gives its actions every method of their port", function ()
	local ENT = {}
	local env = setmetatable (
		{
			ENT = ENT,
			AddCSLuaFile = function () end,
			DEFINE_BASECLASS = function () end,
			Vector = function (x, y, z) return { x = x, y = y, z = z } end,
			ACT_IDLE = 1,
			CLIENT = false,
			SERVER = true
		}, { __index = _G })
	local chunk = assert (loadfile ("addons/nextsoldier/lua/entities/nextbot_cscanner.lua"))
	setfenv (chunk, env) ()
	T.eq (ENT.Base,                 "base_nextbot2")
	T.eq (type (ENT.InitialAction), "function")
	T.eq (type (ENT.PhysicsSimulate), "function", "its motion controller: HL2's physics flyer")
	T.eq (type (ENT.SetupFlight), "function")
	for _, method in ipairs (Scanner.PORT:Methods ()) do
		-- an entity's own, from the engine
		if method ~= "Health" then T.eq (type (ENT [method]), "function", "it defines " .. method) end
	end
	T.eq (rawget (env, "HOVER_HEIGHT"), nil, "its tuning is its own, no global")
end)

T.finish ()
