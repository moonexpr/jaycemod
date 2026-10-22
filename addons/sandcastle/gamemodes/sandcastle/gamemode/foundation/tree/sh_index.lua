-- foundation's trees. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local tree = Namespace("tree")
Export(tree, "heap", require("foundation.tree.heap"))
Export(tree, "avl", require("foundation.tree.avl"))
