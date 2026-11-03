-- Where the tactics engine and NextSoldier meet, the one module that reads
-- both (tests/foundation_layers_test.lua), loaded only when a mode hosting
-- soldiers reads it. It builds the monitors once, as states of NextSoldier's
-- own chart, and gives them to NextSoldier by name. From then on a soldier runs
-- them as any behaviour of its chart: this module is not in the way of a tick.
--
-- The classes are built here, so a live reload of wartactics.monitors takes
-- effect with this module reloaded after it.
local Monitors = wartactics.monitors
local MonitorLib = nextsoldier.monitor
local Behaviors = nextsoldier.behaviors.Shared
module(...)

local Tree = Monitors.Build({ Monitor = MonitorLib.New, Passthrough = MonitorLib.Passthrough })
TacticalMonitor, SquadMonitor, ScenarioMonitor = Tree.TacticalMonitor, Tree.SquadMonitor, Tree.ScenarioMonitor

Behaviors:Register({ name = "TacticalMonitor", behavior = TacticalMonitor })
Behaviors:Register({ name = "SquadMonitor", behavior = SquadMonitor })
Behaviors:Register({ name = "ScenarioMonitor", behavior = ScenarioMonitor })
