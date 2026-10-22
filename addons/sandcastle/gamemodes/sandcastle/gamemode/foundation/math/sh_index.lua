-- foundation's maths, in Lua's math table. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local math = Namespace("math")
Export(math, "geometry", require("foundation.math.geometry"))
Export(math, "scalar", require("foundation.math.scalar"))
Export(math, "stats", require("foundation.math.stats"))
Export(math, "weighted", require("foundation.math.weighted"))
Export(math, "polynomial", require("foundation.math.polynomial"))
Export(math, "matrix", require("foundation.math.matrix"))
Export(math, "polyline", require("foundation.math.polyline"))
