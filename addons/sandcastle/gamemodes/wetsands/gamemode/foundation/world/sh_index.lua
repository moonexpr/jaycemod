-- foundation's lookups: sets, pair maps, the spatial grid, leases, in the
-- world table games' world I/O shares. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local world = Namespace("world")
Twin(world, "sets", require("foundation.world.sets"))
Twin(world, "pairmap", require("foundation.world.pairmap"))
Twin(world, "grid", require("foundation.world.grid"))
Twin(world, "lease", require("foundation.world.lease"))
Twin(world, "bucket", require("foundation.world.bucket"))
