-- The tactical, squad and scenario monitors (docs/aiwar-command.md §1; TF2's
-- CTFBot*Monitor), a level of the tree a soldier runs each:
--
--   TacticalMonitor        what keeps the soldier alive comes first: the
--                          disarmed SuspendFor Humiliated, the hunters
--                          SeekAndDestroy, the hurt RetreatToCover and
--                          CallMedic, an unlocked door OpenDoor
--     SquadMonitor         leader, member or solo (wartactics.squad)
--       SquadLeader | SquadMember | Solo   a member fights its leader's enemy
--         ScenarioMonitor  the scenario's own monitor when it registered one
--                          (wartactics.scenarios), else the mode's side
--
-- A mode hosts them: it enters the tree at TacticalMonitor, registers the
-- behaviours named above with NextSoldier (a soldier's state.behaviors, which
-- refuses a name it was not given), and puts a HOST on the soldier's state
-- (state.host), its answers to what only it knows:
--   Sides(state) -> the action of the member's side, in a scenario with no
--     monitor of its own
--   Hunting(state) -> whether the member hunts its enemies now
--   Treated(state, now) -> whether a medic is treating the member now
--   Scenario(state) -> the scenario entry played now, or nil
-- state.member is the mode's roster entry, as wartactics.squad reads it.
local ipairs, max = ipairs, math.max
local N = npc.nextbot
local Port = core.port
local MonitorLib = nextsoldier.monitor
local Behaviors = nextsoldier.behaviors.Shared
local Squad = wartactics.squad
module(...)

HOST = Port.New("wartactics monitors host", { "Sides", "Hunting", "Treated", "Scenario" })

-- A soldier hurt badly (under RETREAT_HEALTH of its most) or hard
-- (RETREAT_BURST of its most in the last RETREAT_WINDOW seconds) retreats;
-- under CALL_MEDIC_HEALTH of its most it calls for a medic.
RETREAT_HEALTH, RETREAT_BURST, RETREAT_WINDOW = 0.35, 0.4, 3
CALL_MEDIC_HEALTH = 0.75

function HealthShare(me)
	return me:Health() / max(me:MaxHealth(), 1)
end

local Monitor, PassthroughMonitor = MonitorLib.New, MonitorLib.Passthrough

-- ScenarioMonitor: runs the scenario's own monitor when it registered one
-- (by the name it was given NextSoldier under), else the member's side;
-- begins again when the scenario changes.
ScenarioMonitor = PassthroughMonitor("ScenarioMonitor", function(state)
	local scenario = state.host.Scenario(state)
	if scenario and scenario.monitor then return state.behaviors:Get(scenario.monitor):New(state) end
	return state.host.Sides(state)
end)

function ScenarioMonitor:OnStart(me)
	self.scenario = self.state.host.Scenario(self.state)
	return self:Continue()
end

function ScenarioMonitor:Update(me)
	if self.state.host.Scenario(self.state) ~= self.scenario then
		return self:ChangeTo(ScenarioMonitor:New(self.state), "scenario changed")
	end
	return self:Continue()
end

-- The squad roles: each runs the job; which one runs follows the member's
-- place in its squad (wartactics.squad's Kind), changing itself when
-- that changes (a leader died, a hero joined, a new job's squad).
local SquadRoles = {}

local function SquadRole(kind, name)
	local class = Monitor(name, function(state) return ScenarioMonitor:New(state) end)
	class.kind = kind
	function class:Update(me)
		local now = Squad.Kind(self.state.member)
		if now ~= self.kind then return self:ChangeTo(SquadRoles[now]:New(self.state), "now " .. now) end
		return self:Continue()
	end
	SquadRoles[kind] = class
	return class
end

-- SquadLeader: does its job; its squad takes its line, place and enemy from it.
SquadRole("leader", "SquadLeader")

-- SquadMember (TF2's CTFBotEscortSquadLeader): does its job, and fights the
-- enemy its leader fights when that is one of the two DrGBase compares.
local SquadMember = SquadRole("member", "SquadMember")

function SquadMember:SelectMoreDangerousThreat(me, a, b)
	local fireTeam = self.state.member.fireTeam
	local leader = fireTeam and Squad.Leader(fireTeam)
	local focus = leader and leader ~= self.state.member and leader.enemy
	if focus ~= nil and (a == focus or b == focus) then return focus end
	return N.ANSWER_UNDEFINED
end

-- Solo: in no squad (no job yet).
SquadRole("solo", "Solo")

-- SquadMonitor: leader, member or solo.
SquadMonitor = PassthroughMonitor("SquadMonitor", function(state)
	return SquadRoles[Squad.Kind(state.member)]:New(state)
end)

-- TacticalMonitor: what keeps the soldier alive comes before its squad and
-- its job: humiliation, then the hunt of the losers, then retreat, which
-- what it runs may refuse (ShouldRetreat NO); then opening an unlocked door.
TacticalMonitor = PassthroughMonitor("TacticalMonitor", function(state) return SquadMonitor:New(state) end)

-- The damage it took, kept for RETREAT_WINDOW (OnInjured, from DrGBase).
function TacticalMonitor:OnInjured(me, attacker, amount)
	local log = self.state.hurtLog or {}
	log[#log + 1] = { at = me:Now(), amount = amount or 0 }
	self.state.hurtLog = log
	return self:TryContinue()
end

local function RecentDamage(state, now)
	local total, kept = 0, {}
	for _, hurt in ipairs(state.hurtLog or {}) do
		if now - hurt.at <= RETREAT_WINDOW then
			total = total + hurt.amount
			kept[#kept + 1] = hurt
		end
	end
	state.hurtLog = kept
	return total
end

function TacticalMonitor:Update(me)
	local state, now = self.state, me:Now()
	local behaviors, host = state.behaviors, state.host
	if me:IsDisarmed() then return self:SuspendFor(behaviors:Get("Humiliated"):New(state), "humiliated") end
	if host.Hunting(state) then return self:SuspendFor(behaviors:Get("SeekAndDestroy"):New(state), "get the losers") end
	if now >= (state.retreatReadyAt or 0) then
		local badly = HealthShare(me) < RETREAT_HEALTH
		local hard = RecentDamage(state, now) >= RETREAT_BURST * me:MaxHealth()
		if (badly or hard) and self:QueryBelow(me, "ShouldRetreat") ~= N.ANSWER_NO then
			return self:SuspendFor(behaviors:Get("RetreatToCover"):New(state), badly and "badly hurt" or "hurt hard")
		end
	end
	if HealthShare(me) < CALL_MEDIC_HEALTH and now >= (state.medicCallReadyAt or 0) and not host.Treated(state, now) then
		return self:SuspendFor(behaviors:Get("CallMedic"):New(state), "hurt: calling for a medic")
	end
	if now >= (state.doorOpenRetryAt or 0) and me:DoorToOpen() then
		return self:SuspendFor(behaviors:Get("OpenDoor"):New(state), "opening an unlocked door")
	end
	return self:Continue()
end

Behaviors:Register({ name = "TacticalMonitor", behavior = TacticalMonitor })
Behaviors:Register({ name = "SquadMonitor", behavior = SquadMonitor })
Behaviors:Register({ name = "ScenarioMonitor", behavior = ScenarioMonitor })
