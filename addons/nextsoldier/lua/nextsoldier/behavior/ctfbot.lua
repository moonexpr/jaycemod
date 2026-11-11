-- TF2's flag carrier as the engine's own actions, from tf/bot/behavior:
--
--   CLuaBehaviour (a NextBot's; a NextSoldier has none) > TacticalMonitor (native)
--     > ScenarioMonitor (native) > FetchFlag
--                                > DeliverFlag, burying them while it has the flag
--
-- What they ask of the soldier: HasTheFlag(), IsFlagHome(), GetsFlagAsItSpawns(),
-- SecondsAlive(), PickUpFlag(), FlagToFetch() -> where it lies or nil,
-- FlagCaptureZone() -> where it is or nil, FollowPath(goal), Now(), RoundMode().
local Action = nextsoldier.behavior.action
local ipairs = ipairs
module ("nextsoldier.behavior.ctfbot")

-- CTFBotFetchFlag gives a robot the bomb only just as it spawns.
local JUST_SPAWNED = 1

TAUNT_SECONDS = 1.5

-- CTFBotTaunt, without its animation: stands for its time.
Taunt = Action.Extend ("Taunt")

function Taunt:OnStart (me)
	self.endsAt = me:Now () + TAUNT_SECONDS
	return self:Continue ()
end

function Taunt:Update (me)
	if me:Now () >= self.endsAt then return self:Done ("Taunt finished") end
	return self:Continue ()
end

-- CTFBotDeliverFlag: runs it in.
DeliverFlag = Action.Extend ("DeliverFlag")

function DeliverFlag:Update (me)
	if not me:HasTheFlag () then return self:Done ("I'm no longer carrying the flag") end
	local zone = me:FlagCaptureZone ()
	if not zone then return self:Done ("No flag capture zone exists!") end
	me:FollowPath (zone)
	return self:Continue ()
end

function DeliverFlag:ShouldHurry () return Action.ANSWER_YES end
function DeliverFlag:ShouldRetreat () return Action.ANSWER_NO end

-- CTFBotFetchFlag: MvM's bomb as it spawns, else the flag where it lies. Who has it
-- then is the scenario monitor's to see.
FetchFlag = Action.Extend ("FetchFlag")

function FetchFlag:Update (me)
	if me:HasTheFlag () then return self:Continue () end
	if me:IsFlagHome () and me:GetsFlagAsItSpawns () and me:SecondsAlive () < JUST_SPAWNED then
		me:PickUpFlag ()
		return self:Continue ()
	end
	local flag = me:FlagToFetch ()
	if flag then me:FollowPath (flag) end
	return self:Continue ()
end

function FetchFlag:ShouldHurry () return Action.ANSWER_YES end
function FetchFlag:ShouldRetreat () return Action.ANSWER_NO end

-- What a scenario's monitor may name.
local BEHAVIORS =
{
	FetchFlag = function () return FetchFlag:New () end
}

local GIVEN = { Has = function (_, name) return BEHAVIORS [name] ~= nil end }

-- The scenarios this soldier plays, on wartactics.scenarios as its host gives it (no
-- war class is asked of them): the flag in MvM and CTF, and elsewhere nothing.
function Compile (Scenarios)
	local registry = Scenarios.New ()
	for _, mode in ipairs ({ "mvm", "ctf" }) do
		registry:Register ({ name = mode, priority = Scenarios.MODE_PRIORITY, mode = mode, monitor = "FetchFlag", scenario = {} })
	end
	registry:Register ({ name = "nothing", priority = Scenarios.FREEFORM_PRIORITY, scenario = {} })
	return registry:Compile (GIVEN)
end

-- The tree it runs, the native monitors over the scenario chosen from compiled.
function InitialAction (engine, compiled)
	return engine.TacticalMonitor (
		{
			scenario = engine.ScenarioMonitor (
				{
					scenarios = compiled,
					context = function (me) return { mode = me:RoundMode () } end,
					behaviors = BEHAVIORS,
					interrupts =
					{
						{
							when = function (me) return me:HasTheFlag () end,
							action = function () return DeliverFlag:New () end,
							reason = "I've picked up the flag! Running it in..."
						}
					}
				}
			),
			never_retreats = true,
			commands =
			{
				taunt = function () return Taunt:New () end
			}
		}
	)
end
