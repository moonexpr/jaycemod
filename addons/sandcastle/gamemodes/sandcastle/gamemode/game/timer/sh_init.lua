-- NextBot's timers, in GMod's timer table, each loaded the first time it is
-- read. One line a module, never a loop: docs/foundation-game-split-plan.md.
local timer = Namespace("timer")
Defer(timer, "countdown", "game.timer.countdown")
Defer(timer, "interval", "game.timer.interval")
