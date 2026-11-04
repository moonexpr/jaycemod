-- nextsoldier.behavior.ctfbot: TF2's bomb carrier as the engine's Actions. The engine
-- runs them on a server (native/nextsoldier); here each answers a fake soldier.
local T = dofile("tests/harness.lua")
local Action = nextsoldier.behavior.action
local CTFBot = nextsoldier.behavior.ctfbot

local ZONE, DROPPED = { x = 900 }, { x = 200 }

-- A soldier with `fields` over what a just spawned one, its flag at home, answers.
local function Me(fields)
	local me = { carrying = false, home = true, age = 0, zone = ZONE, loose = nil, now = 0, walked = {}, picked = 0 }
	for key, value in pairs(fields or {}) do me[key] = value end
	function me:HasTheFlag() return self.carrying end
	function me:IsFlagHome() return self.home end
	function me:SecondsAlive() return self.age end
	function me:PickUpFlag() self.picked = self.picked + 1 self.carrying = true end
	function me:FlagCaptureZone() return self.zone end
	function me:LooseFlag() return self.loose end
	function me:FollowPath(goal) self.walked[#self.walked + 1] = goal return "moving" end
	function me:Now() return self.now end
	return me
end

local function Named(result, kind, name, reason)
	T.eq(result.type, kind, "the result's kind")
	if name then T.eq(result.action.name, name, "the action") end
	if reason then T.eq(result.reason, reason, "the reason") end
end

T.test("the tree is the native monitor's: it runs the scenario, and a robot never retreats", function()
	local given
	local engine = { TacticalMonitor = function(config) given = config return config end }
	T.eq(CTFBot.InitialAction(engine), given, "what the engine made")
	T.eq(given.scenario.name, "ScenarioMonitor", "its child")
	T.eq(given.never_retreats, true, "MvM's rule")
	T.eq(given.commands.taunt().name, "Taunt", "what it suspends for")
end)

T.test("the scenario monitor starts by fetching the flag", function()
	T.eq(CTFBot.ScenarioMonitor:New():InitialContainedAction(Me()).name, "FetchFlag", "its child")
end)

T.test("with the flag the scenario monitor buries what it runs under its delivery", function()
	local monitor = CTFBot.ScenarioMonitor:New()
	Named(monitor:Update(Me()), Action.CONTINUE)
	Named(monitor:Update(Me({ carrying = true })), Action.SUSPEND_FOR, "DeliverFlag", "I've picked up the flag! Running it in...")
end)

T.test("a robot just spawned is given the flag at home, as CTFBotFetchFlag does", function()
	local me = Me({ age = 0.2 })
	Named(CTFBot.FetchFlag:New():Update(me), Action.CONTINUE)
	T.eq(me.picked, 1, "given")
end)

T.test("out in the world it is not, and it stays put with nothing to walk to", function()
	local me = Me({ age = 30 })
	Named(CTFBot.FetchFlag:New():Update(me), Action.CONTINUE)
	T.eq(me.picked, 0, "not given")
	T.eq(#me.walked, 0, "no walk")
end)

T.test("a flag lying loose is walked to", function()
	local me = Me({ age = 30, home = false, loose = DROPPED })
	Named(CTFBot.FetchFlag:New():Update(me), Action.CONTINUE)
	T.eq(me.walked[1], DROPPED, "to the flag")
end)

T.test("a carrier walks to the capture zone", function()
	local me = Me({ carrying = true })
	Named(CTFBot.DeliverFlag:New():Update(me), Action.CONTINUE)
	T.eq(me.walked[1], ZONE, "to the zone")
end)

T.test("delivery is done when it no longer has the flag, or nowhere to take it", function()
	Named(CTFBot.DeliverFlag:New():Update(Me()), Action.DONE, nil, "I'm no longer carrying the flag")
	Named(CTFBot.DeliverFlag:New():Update(Me({ carrying = true, zone = false })), Action.DONE, nil, "No flag capture zone exists!")
end)

T.test("a carrier hurries and does not retreat", function()
	local deliver = CTFBot.DeliverFlag:New()
	T.eq(deliver:ShouldHurry(), Action.ANSWER_YES, "hurry")
	T.eq(deliver:ShouldRetreat(), Action.ANSWER_NO, "retreat")
end)

T.test("a taunt holds for its time and is done, what it covered resuming", function()
	local me, taunt = Me({ now = 10 }), CTFBot.Taunt:New()
	Named(taunt:OnStart(me), Action.CONTINUE)
	Named(taunt:Update(me), Action.CONTINUE)
	me.now = 10 + CTFBot.TAUNT_SECONDS
	Named(taunt:Update(me), Action.DONE)
end)

T.test("results carry what they name, an event's its priority", function()
	local a = Action.Extend("Probe")
	local other = a:New()
	Named(a:New():ChangeTo(other, "next"), Action.CHANGE_TO, "Probe", "next")
	local tried = a:New():TrySuspendFor(other, Action.RESULT_CRITICAL, "now")
	Named(tried, Action.SUSPEND_FOR, "Probe", "now")
	T.eq(tried.priority, Action.RESULT_CRITICAL, "its priority")
	T.eq(a:New():TryContinue().type, Action.CONTINUE, "tries nothing")
end)

T.finish()
