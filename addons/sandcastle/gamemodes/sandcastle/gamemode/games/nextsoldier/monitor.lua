-- NextSoldier's monitors (docs/aiwar-command.md §1; TF2's CTFBot*Monitor):
-- a monitor is a behaviour, an npc.nextbot Action (generator.hfsm's, on
-- generator.state_chart), holding the soldier's state and containing one
-- behaviour, which contains(state) gives; a monitor's own Update changes
-- what it contains when what it watches changes.
--   New(name, contains) -> a monitor class: Init(state) keeps the state,
--     InitialContainedAction gives contains(state)
--   Passthrough(name, contains) -> the same, only passing through to what
--     it contains, which the debug layer's TDBN leaves out (Action.passthrough)
local N = npc.nextbot
module(...)

function New(name, contains)
	local class = N.Action:Extend(name)
	function class:Init(state) self.state = state end
	function class:InitialContainedAction(me) return contains(self.state) end
	return class
end

function Passthrough(name, contains)
	local class = New(name, contains)
	class.passthrough = true
	return class
end
