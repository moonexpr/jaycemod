-- nextsoldier.behavior.ctfbot: TF2's bomb carrier as the engine's Actions. The engine
-- runs them on a server (addons/nextsoldier/native); here each answers a fake soldier.
local T = dofile ("tests/harness.lua")
local Action = nextsoldier.behavior.action
local CTFBot = nextsoldier.behavior.ctfbot

local ZONE, INTEL = { x = 900 }, { x = 200 }

-- A soldier with `fields` over what one just spawned in MvM, its bomb at home, answers.
local function Me (fields)
	local me = { carrying = false, home = true, atSpawn = true, age = 0, zone = ZONE, fetch = nil, now = 0, walked = {}, picked = 0, mode = "mvm", tend = nil, reach = false, swung = {} }
	for key, value in pairs (fields or {}) do me [key] = value end
	function me:HasTheFlag () return self.carrying end
	function me:IsFlagHome () return self.home end
	function me:GetsFlagAsItSpawns () return self.atSpawn end
	function me:SecondsAlive () return self.age end
	function me:PickUpFlag () self.picked = self.picked + 1 self.carrying = true end
	function me:FlagCaptureZone () return self.zone end
	function me:FlagToFetch () return self.fetch end
	function me:FollowPath (goal) self.walked [#self.walked + 1] = goal return "moving" end
	function me:Now () return self.now end
	function me:RoundMode () return self.mode end
	function me:BuildingToTend () return self.tend end
	function me:WithinWrenchReach (spot) return self.reach end
	function me:SwingAt (spot) self.swung [#self.swung + 1] = spot end
	return me
end

local function Named (result, kind, name, reason)
	T.eq (result.type, kind, "the result's kind")
	if name then T.eq (result.action.name, name, "the action") end
	if reason then T.eq (result.reason, reason, "the reason") end
end

-- An engine that hands back the configs it is given.
local ENGINE =
{
	TacticalMonitor = function (config) return config end,
	ScenarioMonitor = function (config) return config end
}

T.test ("the tree is native monitors over the scenario's actions, and a robot never retreats", function ()
	local compiled = CTFBot.Compile (wartactics.scenarios)
	local tactical = CTFBot.InitialAction (ENGINE, compiled)
	T.eq (tactical.never_retreats,         true,    "MvM's rule")
	T.eq (tactical.commands.taunt ().name, "Taunt", "what it suspends for")
	local scenario = tactical.scenario
	T.eq (scenario.scenarios,                            compiled,    "it reads the registry")
	T.eq (scenario.context (Me ({ mode = "ctf" })).mode, "ctf",       "it chooses by the rounds mode")
	T.eq (scenario.behaviors.FetchFlag ().name,          "FetchFlag", "what a scenario's monitor names")
end)

T.test ("MvM and CTF play the flag, and anything else plays nothing", function ()
	local compiled = CTFBot.Compile (wartactics.scenarios)
	T.eq (compiled:Choose ({ mode = "mvm" }).monitor,  "FetchFlag", "MvM")
	T.eq (compiled:Choose ({ mode = "ctf" }).monitor,  "FetchFlag", "CTF")
	T.eq (compiled:Choose ({ mode = "koth" }).monitor, nil,         "koth")
	T.eq (compiled:Choose ({}).monitor,                nil,         "no rounds")
end)

T.test ("with the flag the scenario monitor's interrupt buries what it runs under its delivery", function ()
	local interrupt = CTFBot.InitialAction (ENGINE, CTFBot.Compile (wartactics.scenarios)).scenario.interrupts [1]
	T.eq (interrupt.when (Me ()),                    false,                                       "no flag")
	T.eq (interrupt.when (Me ({ carrying = true })), true,                                        "the flag")
	T.eq (interrupt.action ().name,                  "DeliverFlag",                               "its delivery")
	T.eq (interrupt.reason,                          "I've picked up the flag! Running it in...", "TF2's reason")
end)

local SENTRY = { x = 400 }

T.test ("a building of its team to tend buries what it runs under its tending, but for the flag", function ()
	local interrupt = CTFBot.InitialAction (ENGINE, CTFBot.Compile (wartactics.scenarios)).scenario.interrupts [2]
	T.eq (interrupt.when (Me ()),                                   false,           "nothing to tend")
	T.eq (interrupt.when (Me ({ tend = SENTRY })),                  true,            "a building")
	T.eq (interrupt.when (Me ({ tend = SENTRY, carrying = true })), false,           "the flag first")
	T.eq (interrupt.action ().name,                                 "TendBuildings", "its tending")
end)

T.test ("a building to tend out of reach is walked to, one within it swung at", function ()
	local far = Me ({ tend = SENTRY })
	Named (CTFBot.TendBuildings:New ():Update (far), Action.CONTINUE)
	T.eq (far.walked [1], SENTRY, "walked to")
	T.eq (#far.swung,     0,      "not swung at from afar")
	local near = Me ({ tend = SENTRY, reach = true })
	Named (CTFBot.TendBuildings:New ():Update (near), Action.CONTINUE)
	T.eq (near.swung [1], SENTRY, "swung at")
	T.eq (#near.walked,   0,      "stood at")
end)

T.test ("tending is done when every building is whole", function ()
	Named (CTFBot.TendBuildings:New ():Update (Me ()), Action.DONE, nil, "Nothing left to tend")
end)

T.test ("a robot just spawned is given the flag at home, as CTFBotFetchFlag does", function ()
	local me = Me ({ age = 0.2 })
	Named (CTFBot.FetchFlag:New ():Update (me), Action.CONTINUE)
	T.eq (me.picked, 1, "given")
end)

T.test ("out in the world it is not, and it stays put with nothing to walk to", function ()
	local me = Me ({ age = 30 })
	Named (CTFBot.FetchFlag:New ():Update (me), Action.CONTINUE)
	T.eq (me.picked,  0, "not given")
	T.eq (#me.walked, 0, "no walk")
end)

T.test ("in CTF it is given nothing, and walks to the flag", function ()
	local me = Me ({ age = 0.2, atSpawn = false, fetch = INTEL, mode = "ctf" })
	Named (CTFBot.FetchFlag:New ():Update (me), Action.CONTINUE)
	T.eq (me.picked,     0,     "not given")
	T.eq (me.walked [1], INTEL, "to the flag")
end)

T.test ("with the flag it walks to nothing: the scenario monitor sees to it", function ()
	local me = Me ({ carrying = true, fetch = INTEL })
	Named (CTFBot.FetchFlag:New ():Update (me), Action.CONTINUE)
	T.eq (#me.walked, 0, "no walk")
end)

T.test ("a carrier walks to the capture zone", function ()
	local me = Me ({ carrying = true })
	Named (CTFBot.DeliverFlag:New ():Update (me), Action.CONTINUE)
	T.eq (me.walked [1], ZONE, "to the zone")
end)

T.test ("delivery is done when it no longer has the flag, or nowhere to take it", function ()
	Named (CTFBot.DeliverFlag:New ():Update (Me ()), Action.DONE, nil, "I'm no longer carrying the flag")
	Named (CTFBot.DeliverFlag:New ():Update (Me ({ carrying = true, zone = false })), Action.DONE, nil, "No flag capture zone exists!")
end)

T.test ("a carrier hurries and does not retreat", function ()
	local deliver = CTFBot.DeliverFlag:New ()
	T.eq (deliver:ShouldHurry (),   Action.ANSWER_YES, "hurry")
	T.eq (deliver:ShouldRetreat (), Action.ANSWER_NO,  "retreat")
end)

T.test ("a taunt holds for its time and is done, what it covered resuming", function ()
	local me, taunt = Me ({ now = 10 }), CTFBot.Taunt:New ()
	Named (taunt:OnStart (me), Action.CONTINUE)
	Named (taunt:Update (me),  Action.CONTINUE)
	me.now = 10 + CTFBot.TAUNT_SECONDS
	Named (taunt:Update (me), Action.DONE)
end)

T.test ("results carry what they name, an event's its priority", function ()
	local a = Action.Extend ("Probe")
	local other = a:New ()
	Named (a:New ():ChangeTo (other, "next"), Action.CHANGE_TO, "Probe", "next")
	local tried = a:New ():TrySuspendFor (other, Action.RESULT_CRITICAL, "now")
	Named (tried, Action.SUSPEND_FOR, "Probe", "now")
	T.eq (tried.priority,               Action.RESULT_CRITICAL, "its priority")
	T.eq (a:New ():TryContinue ().type, Action.CONTINUE,        "tries nothing")
end)

T.finish ()
