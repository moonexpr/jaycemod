-- foundation's trees. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local tree = Namespace("tree")
Twin(tree, "heap", require("foundation.tree.heap"))
Twin(tree, "avl", require("foundation.tree.avl"))
