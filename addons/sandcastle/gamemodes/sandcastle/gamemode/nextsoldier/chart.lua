-- NextSoldier's chart: the contract every behaviour of a soldier is a state
-- of (generator.hfsm's Chart, NextBot's Action/Behavior engine with its
-- stacks). It declares, before any behaviour exists:
--   the port    nextsoldier.soldier's: all a behaviour may ask of its soldier
--   EVENTS      what the soldier and the war tell its behaviours: what the
--               soldier suffers and senses (OnInjured, OnSight, OnLostSight,
--               OnContact, OnContactLost, OnNavAreaChanged), a shot heard
--               (OnHeard) and a death seen (OnOtherKilled)
--   QUERIES     what the soldier asks them, as TF2's bots' contextual
--               queries: ShouldAttack, ShouldHurry, ShouldRetreat,
--               ShouldPickUp, SelectMoreDangerousThreat
-- A behaviour is CHART:State(name), further extended with :Extend(name); one
-- defining an On* that is neither one of these events nor a lifecycle hook
-- (OnStart, OnEnd, OnSuspend, OnResume) is refused as it is written.
-- CHART:New(soldier, first) runs a soldier's chart from its first behaviour.
local Hfsm, Soldier = generator.hfsm, nextsoldier.soldier
module(...)

EVENTS = { "OnInjured", "OnSight", "OnLostSight", "OnContact", "OnContactLost", "OnNavAreaChanged", "OnHeard",
	"OnOtherKilled" }

QUERIES = { "ShouldAttack", "ShouldHurry", "ShouldRetreat", "ShouldPickUp", "SelectMoreDangerousThreat" }

CHART = Hfsm.Chart({
	name = "NextSoldier",
	port = Soldier.PORT,
	events = EVENTS,
	queries = QUERIES,
	initial = function(first) return first end,
})
