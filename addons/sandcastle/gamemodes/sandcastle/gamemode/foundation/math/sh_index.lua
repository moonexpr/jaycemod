-- foundation's maths, in Lua's math table. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local math = Namespace("math")
Twin(math, "geometry", require("foundation.math.geometry"))
Twin(math, "scalar", require("foundation.math.scalar"))
Twin(math, "stats", require("foundation.math.stats"))
Twin(math, "weighted", require("foundation.math.weighted"))
Twin(math, "polynomial", require("foundation.math.polynomial"))
Twin(math, "matrix", require("foundation.math.matrix"))
Twin(math, "polyline", require("foundation.math.polyline"))
