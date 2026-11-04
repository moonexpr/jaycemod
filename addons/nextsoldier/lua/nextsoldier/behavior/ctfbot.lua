-- TF2's bomb carrier as the engine's own actions, from tf/bot/behavior:
--
--   CLuaBehaviour (GMod's) > TacticalMonitor (native/nextsoldier)
--     > ScenarioMonitor > FetchFlag
--                       > DeliverFlag, burying them while it has the flag
--
-- What they ask of the soldier: HasTheFlag(), IsFlagHome(), SecondsAlive(),
-- PickUpFlag(), LooseFlag() -> where it lies or nil, FlagCaptureZone() -> where it is
-- or nil, FollowPath(goal), Now().
local Action = nextsoldier.behavior.action
module("nextsoldier.behavior.ctfbot")

-- CTFBotFetchFlag gives a robot the bomb only just as it spawns.
local JUST_SPAWNED = 1

TAUNT_SECONDS = 1.5

-- CTFBotTaunt, without its animation: stands for its time.
Taunt = Action.Extend("Taunt")

function Taunt:OnStart(me)
	self.endsAt = me:Now() + TAUNT_SECONDS
	return self:Continue()
end

function Taunt:Update(me)
	if me:Now() >= self.endsAt then return self:Done("Taunt finished") end
	return self:Continue()
end

-- CTFBotDeliverFlag: runs it in.
DeliverFlag = Action.Extend("DeliverFlag")

function DeliverFlag:Update(me)
	if not me:HasTheFlag() then return self:Done("I'm no longer carrying the flag") end
	local zone = me:FlagCaptureZone()
	if not zone then return self:Done("No flag capture zone exists!") end
	me:FollowPath(zone)
	return self:Continue()
end

function DeliverFlag:ShouldHurry() return Action.ANSWER_YES end
function DeliverFlag:ShouldRetreat() return Action.ANSWER_NO end

-- CTFBotFetchFlag: the bomb as it spawns, else a dropped one. Who has it then is the
-- scenario monitor's to see.
FetchFlag = Action.Extend("FetchFlag")

function FetchFlag:Update(me)
	if me:HasTheFlag() then return self:Continue() end
	if me:IsFlagHome() then
		if me:SecondsAlive() < JUST_SPAWNED then me:PickUpFlag() end
		return self:Continue()
	end
	local loose = me:LooseFlag()
	if loose then me:FollowPath(loose) end
	return self:Continue()
end

function FetchFlag:ShouldHurry() return Action.ANSWER_YES end
function FetchFlag:ShouldRetreat() return Action.ANSWER_NO end

-- CTFBotScenarioMonitor: what the scenario wants, over what its class is doing.
ScenarioMonitor = Action.Extend("ScenarioMonitor")

function ScenarioMonitor:InitialContainedAction() return FetchFlag:New() end

function ScenarioMonitor:Update(me)
	if me:HasTheFlag() then
		return self:SuspendFor(DeliverFlag:New(), "I've picked up the flag! Running it in...")
	end
	return self:Continue()
end

-- The tree a robot runs: the native monitor over the scenario's.
function InitialAction(engine)
	return engine.TacticalMonitor({
		scenario = ScenarioMonitor:New(),
		never_retreats = true,
		commands = {
			taunt = function() return Taunt:New() end,
		},
	})
end
