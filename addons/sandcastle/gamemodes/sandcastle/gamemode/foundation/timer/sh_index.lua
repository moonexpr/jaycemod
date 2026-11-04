-- foundation's timers, NextBot's, in GMod's timer table. One line a module, never
-- a loop: docs/foundation-game-split-plan.md.
local timer = Namespace("timer")
Twin(timer, "countdown", require("foundation.timer.countdown"))
Twin(timer, "interval", require("foundation.timer.interval"))
