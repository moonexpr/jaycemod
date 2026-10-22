-- The gamemode's core, in GMod's system table: game events, features, the
-- gamemode's state, permissions, play modes, spawning and idling, each
-- loaded the first time it is read. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local system = Namespace("system")
Defer(system, "events", "games.system.events")
Defer(system, "features", "games.system.features")
Defer(system, "gamemode", "games.system.gamemode")
Defer(system, "permissions", "games.system.permissions")
Defer(system, "play_mode", "games.system.play_mode")
Defer(system, "spawn_manager", "games.system.spawn_manager")
Defer(system, "idle", "games.system.idle")
