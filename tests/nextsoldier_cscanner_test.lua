-- nextsoldier.behavior.cscanner: HL2's city scanner as a family of actions (nextbot_cscanner's).
-- The family's responders are three questions, ShouldEvacuate, ShouldAttack and ShouldFollow,
-- which every scanner action answers for itself; its monitor asks them of what it runs and
-- suspends for the most urgent, each action keeping on while its own answer holds.
local T = dofile ("tests/harness.lua")
local Action = nextsoldier.behavior.action
local Scanner = nextsoldier.behavior.cscanner
local Registry = action_registry
local Geometry = math.geometry
local StateChart = generator.state_chart

for _, name in ipairs ({ "PATROL_REACH", "PATROL_REST", "FOLLOW_DISTANCE", "FOLLOW_LOSE", "PHOTO_RANGE",
	"PHOTO_INTERVAL", "ATTACK_DISTANCE", "FLASH_RANGE", "FLASH_INTERVAL", "EVACUATE_HEALTH", "HURT_WINDOW",
	"EVACUATE_DISTANCE", "EVACUATE_SECONDS" }) do
		T.defined (Scanner [name], name)
	end

local YES, NO = Action.ANSWER_YES, Action.ANSWER_NO

-- A scanner as its actions see it: where it is, its health and clock, who it inspects and who it
-- fights (each a handle and where it is), when it was last hurt, the spots it patrols; what it
-- was told to fly to and whom it flashed are the test's to read. Ask goes to the machine running
-- it, as a bot's intention would.
local function Fake ()
	local me = { pos = { x = 0, y = 0, z = 0 }, health = 40, maxHealth = 40, now = 0, spots = {}, flown = nil,
		hovering = false, flashes = {} }
	function me:Now () return self.now end
	function me:Health () return self.health end
	function me:MaxHealth () return self.maxHealth end
	function me:Position () return self.pos end
	function me:Target () return self.target end
	function me:TargetPosition () return self.targetPos end
	function me:Enemy () return self.enemy end
	function me:EnemyPosition () return self.enemyPos end
	function me:HurtSince (t) return self.hurtAt ~= nil and self.hurtAt > t end
	function me:PatrolSpot () return table.remove (self.spots, 1) end
	function me:FlyTo (p) self.flown, self.hovering = p, false end
	function me:Hover () self.flown, self.hovering = nil, true end
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

T.test ("a player it sees it follows, keeping its distance and photographing them", function ()
	local me = Running ()
	me:Tick ()
	me.target, me.targetPos = "alyx", { x = 1000, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerFollow")
	T.near (Geometry.Distance2D (me.flown, me.targetPos), Scanner.FOLLOW_DISTANCE, 0.01, "stands off")
	T.eq (#me.flashes, 0, "out of range: no photograph")
	me.pos = { x = 1000 - Scanner.FOLLOW_DISTANCE, y = 0, z = 0 }
	me:Tick ()
	T.eq (#me.flashes, 1, "in range: a photograph")
	T.eq (me.flashes [1].who, "alyx")
	me:Tick ()
	T.eq (#me.flashes, 1, "not again so soon")
	me:Tick (Scanner.PHOTO_INTERVAL)
	T.eq (#me.flashes, 2, "again after its interval")
	me.target, me.targetPos = nil, nil
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerPatrol", "lost them: back to its patrol")
end)

T.test ("one too far away is let go", function ()
	local me = Running ()
	me:Tick ()
	me.target, me.targetPos = "alyx", { x = 200, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerFollow")
	me.targetPos = { x = Scanner.FOLLOW_LOSE + 1, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerPatrol")
end)

T.test ("an enemy it attacks, over anyone it follows, flashing it on its interval", function ()
	local me = Running ()
	me:Tick ()
	me.target, me.targetPos = "alyx", { x = 200, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	me.enemy, me.enemyPos = "combine", { x = 0, y = 600, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerAttack", "attacking comes first")
	T.near (Geometry.Distance2D (me.flown, me.enemyPos), Scanner.ATTACK_DISTANCE, 0.01, "closes in")
	local before = #me.flashes
	me.pos = { x = 0, y = 600 - Scanner.ATTACK_DISTANCE, z = 0 }
	me:Tick ()
	T.eq (#me.flashes,                  before + 1)
	T.eq (me.flashes [#me.flashes].who, "combine")
	me:Tick ()
	T.eq (#me.flashes, before + 1, "not again so soon")
	me:Tick (Scanner.FLASH_INTERVAL)
	T.eq (#me.flashes, before + 2)
	me.enemy, me.enemyPos = nil, nil
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerFollow", "its enemy gone: back to whom it followed")
end)

T.test ("badly hurt, it evacuates away from its enemy, over attacking, once until hurt again", function ()
	local me = Running ()
	me:Tick ()
	me.enemy, me.enemyPos = "combine", { x = 300, y = 0, z = 0 }
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerAttack")
	me.health = me.maxHealth * Scanner.EVACUATE_HEALTH
	me.hurtAt = me.now
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (),    "ScannerEvacuate", "evacuating comes first")
	T.eq (me.flown.x < 0, true,              "away from its enemy")
	T.near (Geometry.Distance2D (me.flown, me.pos), Scanner.EVACUATE_DISTANCE, 0.01)
	me:Tick (Scanner.EVACUATE_SECONDS)
	me:Tick ()
	T.eq (me:Doing () ~= "ScannerEvacuate", true, "evacuated, it goes on")
	me:Tick ()
	T.eq (me:Doing () ~= "ScannerEvacuate", true, "not again for the same hurt")
	me.hurtAt = me.now
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerEvacuate", "hurt again")
end)

T.test ("hurt but whole enough, it fights on", function ()
	local me = Running ()
	me:Tick ()
	me.enemy, me.enemyPos = "combine", { x = 300, y = 0, z = 0 }
	me.health, me.hurtAt = me.maxHealth * Scanner.EVACUATE_HEALTH + 1, 0.05
	me:Tick ()
	me:Tick ()
	T.eq (me:Doing (), "ScannerAttack")
end)

T.test ("its answers, as the soldier's intention is asked them", function ()
	local me = Running ()
	me:Tick ()
	T.eq (me:Ask ("ShouldFollow"),   NO)
	T.eq (me:Ask ("ShouldAttack"),   NO)
	T.eq (me:Ask ("ShouldEvacuate"), NO)
	me.target, me.targetPos = "alyx", { x = 200, y = 0, z = 0 }
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
	for _, method in ipairs (Scanner.PORT.methods:Members ()) do
		-- an entity's own, from the engine
		if method ~= "Health" then T.eq (type (ENT [method]), "function", "it defines " .. method) end
	end
	T.eq (rawget (env, "HOVER_HEIGHT"), nil, "its tuning is its own, no global")
end)

T.finish ()
