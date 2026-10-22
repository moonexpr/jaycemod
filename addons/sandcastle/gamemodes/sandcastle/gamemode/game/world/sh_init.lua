-- The world: a map's entity I/O and models as plain data, each loaded the
-- first time it is read. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local world = Namespace("world")
Defer(world, "io", "game.world.io")
Defer(world, "snapshot", "game.world.snapshot")
