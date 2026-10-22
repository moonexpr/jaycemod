-- foundation's graph algorithms. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local graph = Namespace("graph")
Export(graph, "search", require("foundation.graph.search"))
