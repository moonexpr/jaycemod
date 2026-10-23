-- foundation's lookups: sets, pair maps, the spatial grid, leases, in the
-- world table games' world I/O shares. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local world = Namespace("world")
Export(world, "sets", require("foundation.world.sets"))
Export(world, "pairmap", require("foundation.world.pairmap"))
Export(world, "grid", require("foundation.world.grid"))
Export(world, "lease", require("foundation.world.lease"))
