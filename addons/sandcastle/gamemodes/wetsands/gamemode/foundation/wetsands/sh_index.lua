-- foundation.wetsands: the systems moved out of games/ to stand on native
-- backing (native/wetsands, docs/native-foundation-plan.md), the one part of
-- foundation that names game things. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local wetsands = Namespace("wetsands")
Twin(wetsands, "path", require("foundation.wetsands.path"))
Twin(wetsands, "navsearch", require("foundation.wetsands.navsearch"))
