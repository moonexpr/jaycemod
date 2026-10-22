-- foundation's lookups: sets, pair maps, the spatial grid, leases. One line
-- a module, never a loop: docs/foundation-game-split-plan.md.
local map = Namespace("map")
Export(map, "sets", require("foundation.map.sets"))
Export(map, "pairmap", require("foundation.map.pairmap"))
Export(map, "grid", require("foundation.map.grid"))
Export(map, "lease", require("foundation.map.lease"))
