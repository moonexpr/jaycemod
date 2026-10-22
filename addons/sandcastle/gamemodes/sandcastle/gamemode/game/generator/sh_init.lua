-- game's state machines, beside foundation's, each loaded the first time it
-- is read. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local generator = Namespace("generator")
Defer(generator, "hfsm", "game.generator.hfsm")
