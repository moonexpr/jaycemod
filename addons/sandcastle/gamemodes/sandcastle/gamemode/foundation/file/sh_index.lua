-- foundation's binary values, in GMod's file table. One line a module,
-- never a loop: docs/foundation-game-split-plan.md.
local file = Namespace("file")
Export(file, "buffer", require("foundation.file.buffer"))
