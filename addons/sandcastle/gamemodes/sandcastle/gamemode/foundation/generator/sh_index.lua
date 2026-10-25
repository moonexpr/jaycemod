-- foundation's state machines. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local generator = Namespace("generator")
Twin(generator, "state_machine", require("foundation.generator.state_machine"))
Export(generator, "state_chart", require("foundation.generator.state_chart"))
