-- Where the tactics engine and NextSoldier meet, the one module that reads
-- both (tests/foundation_layers_test.lua), loaded only when a mode hosting
-- soldiers reads it. It builds the monitors once, as states of NextSoldier's
-- own chart, and gives them to NextSoldier by name. From then on a soldier runs
-- them as any behaviour of its chart: this module is not in the way of a tick.
--
-- The classes are built here, so a live reload of wartactics.monitors takes
-- effect with this module reloaded after it.
local Monitors = wartactics.monitors
local MonitorLib = nextsoldier.behavior.monitor
local Behaviors = nextsoldier.behavior.registry.Shared
local Policy = wartactics.overwatch
local Director = nextsoldier.squad.interactions.director
local setmetatable = setmetatable
module (...)

local Tree = Monitors.Build ({ Monitor = MonitorLib.New, Passthrough = MonitorLib.Passthrough })
TacticalMonitor, SquadMonitor, ScenarioMonitor = Tree.TacticalMonitor, Tree.SquadMonitor, Tree.ScenarioMonitor

Behaviors:Register ({ name = "TacticalMonitor", behavior = TacticalMonitor })
Behaviors:Register ({ name = "SquadMonitor", behavior = SquadMonitor })
Behaviors:Register ({ name = "ScenarioMonitor", behavior = ScenarioMonitor })

-- A squad's director on Overwatch's policy (wartactics.overwatch), for a mode to give its squads
-- (nextsoldier.squad.interactions.director's Set): each request is answered at once over the radio,
-- from the squad's size and losses, the guards it has lost holding its place (as many as the request
-- reports, all told; else one more each request),
-- whether it has met the enemy, and where to strike (opts.target(order), nil for nowhere known).
function Overwatch (opts)
	local missing = setmetatable ({}, { __mode = "k" })
	return
	{
		Request = function (_, order, request)
			missing [order] = request and request.missing or (missing [order] or 0) + 1
			local decision = Policy.Decide ({ size = order.size, lost = order.lost, missing = missing [order],
				contact = order:Engaged (), target = opts.target (order) })
			Director.Answer (order, decision.kind, decision)
		end
	}
end
