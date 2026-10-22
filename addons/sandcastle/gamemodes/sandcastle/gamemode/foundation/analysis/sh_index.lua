-- foundation's measurements: timers and counters, memory. One line a
-- module, never a loop: docs/foundation-game-split-plan.md.
local analysis = Namespace("analysis")
Export(analysis, "analytics", require("foundation.analysis.analytics"))
Export(analysis, "memory", require("foundation.analysis.memory"))
