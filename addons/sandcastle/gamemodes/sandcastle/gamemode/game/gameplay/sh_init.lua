-- Gameplay's interfaces, each loaded the first time it is read. One line a
-- module, never a loop: docs/foundation-game-split-plan.md.
local gameplay = Namespace("gameplay")
Defer(gameplay, "tactics", "game.gameplay.tactics")
