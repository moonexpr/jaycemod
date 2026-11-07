-- The nbdebug feature's two ends and its command file agree: the view
-- listens to the game events the controllers fire, the feature's shared
-- part defines them (their fields and widths, for both realms), and every
-- command the realm file registers has a handler.
local T = dofile("tests/harness.lua")

local ROOT = T.ROOT
local COMMANDS = ROOT .. "sv_nbdebug.lua"
local NEXTSOLDIER = T.ADDON_TREES.nextsoldier .. "entities/base_nextsoldier.lua"
local WAR_SOLDIER = ROOT .. "sh_war_soldier.lua"
local PATHFOLLOWER = ROOT .. "../entities/entities/npc_pathfollower.lua"
local NAV_CLEARANCE = ROOT .. "includes/nav_clearance.lua"
local NAV = ROOT .. "sv_nav.lua"
local BOT_SOLDIER = ROOT .. "features/aiwar/sv_bot_soldier.lua"
local BOT_NAVIGATOR = ROOT .. "../entities/entities/ws_bot_navigator.lua"

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
local nextsoldier, warSoldier = ReadFile(NEXTSOLDIER), ReadFile(WAR_SOLDIER)
local pathfollower = ReadFile(PATHFOLLOWER)
local navClearance, nav, botSoldier = ReadFile(NAV_CLEARANCE), ReadFile(NAV), ReadFile(BOT_SOLDIER)
local botNavigator = ReadFile(BOT_NAVIGATOR)

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
	T.eq(controller:find("nextsoldier.bots", 1, true) ~= nil, true, "base registry")
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

T.test("bot player path searches report to the PATH layer", function()
	T.eq(controller:find("ent:IsPlayer() and ent:IsBot()", 1, true) ~= nil, true, "recognizes AI-war player bots")
	local sync = assert(controller:find("ent.NSDebugPathWatch = watch", 1, true))
	local sameWatchReturn = assert(controller:find("if same then return end", 1, true))
	T.eq(sync < sameWatchReturn, true, "synchronizes the navigator owner even when the watch is unchanged")
	T.eq(botNavigator:find('WS.require("features.nbdebug.model")', 1, true) ~= nil, true, "uses the PATH report contract")
	T.eq(botNavigator:find('hook.Run("WSNpcPathComputed", owner', 1, true) ~= nil, true, "reports the search as the player bot")
	T.eq(botNavigator:find("Debug.MoveOfSegment(segment.type)", 1, true) ~= nil, true, "preserves route move types")
	T.eq(aiwar:find('found[ent] = entry.npc', 1, true) ~= nil, true, "bot players are registered for selection")
end)

T.test("the path follower exposes its Idle and Travel behavior transitions", function()
	T.eq(pathfollower:find("self:NSDebugBehaviorChanged(previous, name)", 1, true) ~= nil, true, "Idle transition")
	T.eq(pathfollower:find('self:NSDebugBehaviorChanged(previous, "Travel")', 1, true) ~= nil, true, "Travel transition")
end)

T.test("the shared path generator rejects areas and openings the agent's collision hull cannot fit", function()
	T.eq(navClearance:find("entity:GetCollisionBounds()", 1, true) ~= nil, true, "reads any entity's current hull")
	T.eq(navClearance:find("function Clearance:Area(area)", 1, true) ~= nil, true, "tests destination clearance")
	T.eq(navClearance:find("function Clearance:Link(from, to)", 1, true) ~= nil, true, "tests crossing clearance")
	T.eq(navClearance:find("NavGaps.FitLines(", 1, true) ~= nil, true, "checks possible crossings along an opening")
	T.eq(navClearance:find("endpos = to", 1, true) ~= nil, true, "sweeps along the crossing direction")
	T.eq(nav:find("function WS.NavHullClearance(entity, mask)", 1, true) ~= nil, true, "navigation-layer API")
	T.eq(nextsoldier:find("Host.current:PathClearance(self)", 1, true) ~= nil, true, "NextBot uses the shared primitive")
	T.eq(nextsoldier:find("return cost(area, fromArea, ladder, elevator, length, fits)", 1, true) ~= nil, true, "passes clearance to the cost pipeline")
	T.eq(nextsoldier:find("if fits == false then return -1 end", 1, true) ~= nil, true, "default generator rejects an unfit area")
	T.eq(nextsoldier:find("Walkable(fromArea:ComputeAdjacentConnectionHeightChange(area)", 1, true) ~= nil, true, "default generator rejects a rise beyond the body's jump")
	T.eq(warSoldier:find("Base().GetPathGenerator(self, self.NSPathCost() or NoPath)", 1, true) ~= nil, true, "combat costs go through the shared generator")
	T.eq(botSoldier:find("WS.NavHullClearance(self.ent, WS.ClipMasks().brushes)", 1, true) ~= nil, true, "bot players use their player hull")
	T.eq(botSoldier:find("not clearance:Area(area)", 1, true) ~= nil, true, "bot player routes reject an unfit area")
	T.eq(botSoldier:find("not clearance:Link(fromArea, area)", 1, true) ~= nil, true, "bot player routes reject an unfit opening")
	T.eq(pathfollower:find("FitsArea", 1, true), nil, "the probe adds no clearance rule")
end)

T.test("the path follower stool sets what its selected followers answer", function()
	local stool = ReadFile("addons/sandcastle/gamemodes/sandcastle/entities/weapons/gmod_tool/stools/ns_pathfollower.lua")
	T.eq(stool:find("nextsoldier.behavior.YES_NO_QUERIES", 1, true) ~= nil, true, "a box for each yes-or-no query")
	T.eq(stool:find("panel:CheckBox(", 1, true) ~= nil, true, "the boxes")
	T.eq(stool:find("follower:NSRespond(name,", 1, true) ~= nil, true, "the boxes reach the follower")
	T.eq(pathfollower:find("self.nsResponder = Behavior.Responder()", 1, true) ~= nil, true, "a tool follower is asked")
end)

T.test("the path follower stool holds its followers' feet: each plans and shows its path instead", function()
	local stool = ReadFile("addons/sandcastle/gamemodes/sandcastle/entities/weapons/gmod_tool/stools/ns_pathfollower.lua")
	T.eq(stool:find("\"ns_pathfollower_hold\"", 1, true) ~= nil, true, "one box for every mode")
	T.eq(stool:find("ent:NSHoldFeet(hold)", 1, true) ~= nil, true, "the box reaches the follower")
	T.eq(pathfollower:find("NSShowPathOnly", 1, true), nil, "no path-only of its own: the war soldier's held feet")
	T.eq(warSoldier:find("self:PlanPath(target, PATH_TOLERANCE)", 1, true) ~= nil, true, "the path it would walk")
	T.eq(nextsoldier:find("function ENT:PlanPath(", 1, true) ~= nil, true, "as the base plans one it follows")
	T.eq(nextsoldier:find("= self:PlanPath(goal, tolerance)", 1, true) ~= nil, true, "the same planning")
end)

T.test("one follower is driven by the stool's mode: its bench, its legs alone, or the war", function()
	local stool = ReadFile("addons/sandcastle/gamemodes/sandcastle/entities/weapons/gmod_tool/stools/ns_pathfollower.lua")
	T.eq(stool:find("follower:NSSetDriver(", 1, true) ~= nil, true, "the stool sets it")
	T.eq(pathfollower:find("function ENT:NSSetDriver(driver)", 1, true) ~= nil, true, "the follower switches")
	T.eq(pathfollower:find("nextsoldier.engine.End(self)", 1, true) ~= nil, true, "its tree ended")
	T.eq(pathfollower:find("nextsoldier.engine.Insert(self, action)", 1, true) ~= nil, true, "and the driver's put in")
	T.eq(pathfollower:find("if self.nsStarted then", 1, true) ~= nil, true, "once the bot has started: before, its start puts it in")
	T.eq(pathfollower:find("controller:Enlist(self, self:NSTeam(), false)", 1, true) ~= nil, true, "in the war, enlisted")
	T.eq(pathfollower:find("controller:Discharge(self)", 1, true) ~= nil, true, "and let go")
end)

T.test("a follower on its legs fights where they take it, as a soldier on the cart does", function()
	T.eq(pathfollower:find('if driver == "path" then return end', 1, true) ~= nil, true,
		"it looks and attacks unless on its bench")
	T.eq(pathfollower:find('if self:NSDriver() == "legs" then return true end\n\t\treturn hook(self, enemy)', 1, true) ~= nil,
		true, "its legs keep its feet: the intention's idle and fighting hooks leave them be")
	T.eq(pathfollower:find("function ENT:NSSteer(enemy)\n\tlocal result = SoldierSteer(self, enemy)", 1, true) ~= nil, true,
		"and its legs still walk it by the soldier's steering")
	T.eq(pathfollower:find('self:SetNoTarget(self.NSToolManaged and driver == "path")', 1, true) ~= nil, true,
		"only its bench keeps it out of sight, as only its bench keeps it unhurt")
	T.eq(pathfollower:find('WS.Feature("aiwar"):RelateToFactions(self, team)', 1, true) ~= nil, true,
		"its team's enemies are its own, as a soldier's are")
end)

T.test("followers pass through each other, as an engine group of scripted NPCs", function()
	T.eq(pathfollower:find("self:SetCollisionGroup(COLLISION_GROUP_NPC_SCRIPTED)", 1, true) ~= nil, true,
		"a NextBot's own movement asks the engine's collision groups, not GMod's ShouldCollide")
	T.eq(pathfollower:find("ShouldCollide", 1, true), nil, "no hook its movement would not ask")
end)

T.test("a follower speaks its squad's radio calls in chat and the console, and raises its room's alarms", function()
	T.eq(pathfollower:find("function ENT:NSLegsSay(line, call)", 1, true) ~= nil, true, "a call and who it is between")
	T.eq(pathfollower:find("function ENT:NSLegsNameOf(member)", 1, true) ~= nil, true, "each named on the radio")
	T.eq(pathfollower:find("RadioNames[self] = self.NSRadioName", 1, true) ~= nil, true,
		"its name kept apart from it, so one gone missing is still named")
	T.eq(pathfollower:find('"Overwatch"', 1, true) ~= nil, true, "the Combine's director")
	T.eq(pathfollower:find('if call and call.call == "STACK_UP" then RaiseAlarms(self:NSLegsOrder()) end', 1, true) ~= nil, true,
		"stacking up raises the room's alarms")
	local alarm = ReadFile(ROOT .. "../entities/entities/ent_room_alarm.lua")
	T.eq(alarm:find("function ENT:Raise()", 1, true) ~= nil, true, "an alarm raised")
	T.eq(alarm:find('self:TriggerOutput("OnAlarm"', 1, true) ~= nil, true, "its output for the map")
end)

T.test("a follower on its legs runs two stacks: a squad member's main stack and its leggings beside it", function()
	T.eq(pathfollower:find('if driver == "legs" then return nextsoldier.squad.behaviors.member.SquadMember:New() end', 1, true) ~= nil,
		true, "its main stack fights")
	T.eq(pathfollower:find("nextsoldier.engine.InsertGroup(self, GroupIdentity.InitialAction(", 1, true) ~= nil, true,
		"its leggings beside it")
	T.eq(pathfollower:find("nextsoldier.engine.UpdateGroup(self)", 1, true) ~= nil, true, "updated each tick")
	T.eq(pathfollower:find("nextsoldier.engine.EndGroup(self)", 1, true) ~= nil, true, "and ended with it")
	T.eq(pathfollower:find("self.NSBrain = self.nsStackBrain", 1, true) ~= nil, true, "its main stack answers what it is asked")
end)

T.test("a follower on its legs walks to within the legs' reach of its spot, not the soldier's tolerance", function()
	T.eq(warSoldier:find("local tolerance = self.NSGoalTolerance or GOAL_TOLERANCE", 1, true) ~= nil, true,
		"a soldier's goal tolerance may be its own")
	T.eq(pathfollower:find('self.NSGoalTolerance = driver == "legs" and LEGS_REACH or nil', 1, true) ~= nil, true,
		"its legs set theirs, and give it back")
	T.eq(pathfollower:find("local LEGS_REACH = math.min(GIB.STAGE_REACH, REST_REACH) * 3 / 4", 1, true) ~= nil, true,
		"within the reach its legs count as there")
end)

T.test("the path follower uses the combat soldier's path costs", function()
	T.eq(pathfollower:find('WS.Feature("aiwar")', 1, true) ~= nil, true, "AI-war path cost provider")
	T.eq(pathfollower:find("if not aiwar.war then return nil, aiwar end", 1, true) ~= nil, true, "cost provider without active war")
	T.eq(pathfollower:find("aiwar:SoldierPathCost(team", 1, true) ~= nil, true, "shared soldier path cost")
	T.eq(pathfollower:find("return SoldierComputePath(self, from, to, ladder)", 1, true) ~= nil, true,
		"keeps the combat soldier's link rule, past its legs' kept-out areas")
end)

T.test("a war's bot player steers as a NextSoldier does, on the shared steering", function()
	T.eq(botSoldier:find("features.npc.bot_steering", 1, true) ~= nil, true, "its traces")
	T.eq(botSoldier:find("self:StandOnRoute(", 1, true) ~= nil, true, "its route's points where its body fits")
	T.eq(botSoldier:find("self:SteerOn(", 1, true) ~= nil, true, "off a ledge and off a jamb")
end)

T.test("what a head logged reaches the overlay beside the behaviour's lines", function()
	local file = assert(io.open(ROOT .. "features/nbdebug/sv.lua"))
	local controller = file:read("*a")
	file:close()
	T.eq(controller:find("npc:LookLines(now)", 1, true) ~= nil, true, "read as the layer sends")
	T.eq(controller:find("npc:WatchLook(", 1, true) ~= nil, true, "logged only while wanted")
end)

T.test("in the war, the stool sets the conditions its followers' orders meet", function()
	local stool = ReadFile("addons/sandcastle/gamemodes/sandcastle/entities/weapons/gmod_tool/stools/ns_pathfollower.lua")
	T.eq(stool:find("wartactics.fireteam.Report(", 1, true) ~= nil, true, "a contact reported as a member's sighting is")
	T.eq(stool:find("fireTeam.lanesOff", 1, true) ~= nil, true, "lanes toggled on their squads")
	T.eq(warSoldier:find("if self.NSFeetHeld then return self:NSShowHeldPath(enemy) end", 1, true) ~= nil, true,
		"a held soldier plans and shows its path instead of walking it")
end)

T.test("annotating, the stool marks the map through the war's and the builder's own calls", function()
	local stool = ReadFile("addons/sandcastle/gamemodes/sandcastle/entities/weapons/gmod_tool/stools/ns_pathfollower.lua")
	T.eq(stool:find('WS.Feature("builder"):Do("Place", ply, trace,', 1, true) ~= nil, true, "objectives placed as the Gameplay tools do")
	T.eq(stool:find('WS.Feature("aiwar"):Mark(kind, PanelTeam(tool), at)', 1, true) ~= nil, true, "marks given to the war")
	T.eq(stool:find("controller:GiveMission(fireTeam, kind, at)", 1, true) ~= nil, true, "a squad's mission by hand")
	T.eq(stool:find(":Unmark(trace.HitPos, UNMARK_REACH)", 1, true) ~= nil, true, "marks taken back")
end)

T.finish()
