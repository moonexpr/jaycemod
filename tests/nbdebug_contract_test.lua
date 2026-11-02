-- The nbdebug feature's two ends and its command file agree: the view
-- listens to the game events the controllers fire, the feature's shared
-- part defines them (their fields and widths, for both realms), and every
-- command the realm file registers has a handler.
local T = dofile("tests/harness.lua")

local ROOT = T.ROOT
local COMMANDS = ROOT .. "ws/sv_nbdebug.lua"
local NEXTSOLDIER = ROOT .. "../entities/entities/base_nextsoldier.lua"
local PATHFOLLOWER = ROOT .. "../entities/entities/npc_pathfollower.lua"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- The game event names a text fires, listens to or defines, as a set.
local function Names(text, call)
	local found = {}
	for name in text:gmatch(call .. "%(\"([%w_]+)\"") do found[name] = true end
	return found
end

local controller, view = T.RealmSource("nbdebug", "sv"), T.RealmSource("nbdebug", "cl")
local shared = T.RealmSource("nbdebug", "sh")
local aiwar = T.RealmSource("aiwar", "sv")
local nextsoldier, pathfollower = ReadFile(NEXTSOLDIER), ReadFile(PATHFOLLOWER)

-- What the nbdebug controller fires, and the AI war's overlay.
local function Fired()
	local fired = Names(controller, "Events%.Fire")
	fired.game_aiwar_debug = Names(aiwar, "Events%.Fire").game_aiwar_debug
	return fired
end

T.test("the view listens to every game event the controllers fire", function()
	local heard, count = Names(view, "Listen"), 0
	for name in pairs(Fired()) do
		count = count + 1
		T.eq(heard[name], true, "a listener for " .. name)
	end
	T.eq(count >= 7, true, "the events were found")
end)

T.test("every game event they fire is defined in the feature's shared part, for both realms", function()
	local defined = Names(shared, "Define")
	for name in pairs(Fired()) do T.eq(defined[name], true, name .. " defined in sh.lua") end
end)

T.test("the controller's game events are named game_nb_debug_<subject>", function()
	for name in pairs(Names(controller, "Events%.Fire")) do
		T.eq(name:match("^game_nb_debug_[a-z_]+$") ~= nil, true, name)
	end
end)

T.test("every command the realm file registers has a handler in the controller", function()
	local commands = ReadFile(COMMANDS)
	local count = 0
	for name in commands:gmatch('name = "(ws_nb_[%a_]+)"') do
		count = count + 1
		T.eq(controller:find("COMMANDS." .. name .. " = function", 1, true) ~= nil, true, name)
	end
	T.eq(count, 5, "five commands")
end)

T.test("the debug controller includes every live base_nextsoldier not already registered", function()
	T.eq(controller:find("WS.NextSoldierBots", 1, true) ~= nil, true, "base registry")
	T.eq(controller:find("found[ent] == nil", 1, true) ~= nil, true, "preserves richer providers")
	T.eq(controller:find("ent:NSDebugStack()", 1, true) ~= nil, true, "generic behavior stack")
	T.eq(controller:find("ent:NSDebugWatch(log)", 1, true) ~= nil, true, "generic behavior watch")
end)

T.test("base_nextsoldier reports watched path searches and records the passed cost generator", function()
	T.eq(nextsoldier:find("self.NSDebugPathWatch", 1, true) ~= nil, true, "path watch")
	T.eq(nextsoldier:find("recorder:Record(area:GetID()", 1, true) ~= nil, true, "cost calls")
	T.eq(nextsoldier:find("path:GetAllSegments() or {}", 1, true) ~= nil, true, "unreachable paths have no segments")
	T.eq(nextsoldier:find('hook.Run("WSNpcPathComputed"', 1, true) ~= nil, true, "path report")
end)

T.test("the PATH layer draws each watched NextSoldier's live engine path and goal sphere", function()
	T.eq(controller:find("sub:Wants(bot, Debug.PATH)", 1, true) ~= nil, true, "only PATH viewers enable it")
	T.eq(controller:find("ent.NSDebugDrawPath = true", 1, true) ~= nil, true, "sets the base draw flag")
	T.eq(nextsoldier:find("if self.NSDebugDrawPath then", 1, true) ~= nil, true, "base draws only while watched")
	T.eq(nextsoldier:find("path:Draw()", 1, true) ~= nil, true, "engine path overlay")
	T.eq(view:find("render.DrawWireframeSphere(path.goal", 1, true) ~= nil, true, "client goal sphere")
end)

T.test("the path follower exposes its Idle and Travel behavior transitions", function()
	T.eq(pathfollower:find("self:NSDebugBehaviorChanged(previous, name)", 1, true) ~= nil, true, "Idle transition")
	T.eq(pathfollower:find('self:NSDebugBehaviorChanged(previous, "Travel")', 1, true) ~= nil, true, "Travel transition")
end)

T.test("the path follower uses the combat soldier's path costs without its own hull-based link rejection", function()
	T.eq(pathfollower:find('WS.Feature("aiwar")', 1, true) ~= nil, true, "AI-war path cost provider")
	T.eq(pathfollower:find("if not aiwar.war then return nil, aiwar end", 1, true) ~= nil, true, "cost provider without active war")
	T.eq(pathfollower:find("aiwar:SoldierPathCost(team", 1, true) ~= nil, true, "shared soldier path cost")
	T.eq(pathfollower:find("HasPathClearance", 1, true), nil, "no additional link rejection")
	T.eq(pathfollower:find("function ENT:OnComputePath", 1, true), nil, "inherits the combat soldier's link rule")
end)

T.finish()
