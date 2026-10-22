-- foundation's text and archive formats. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local encoding = Namespace("encoding")
Export(encoding, "cursor", require("foundation.encoding.cursor"))
Export(encoding, "utf16", require("foundation.encoding.utf16"))
Export(encoding, "keyvalues", require("foundation.encoding.keyvalues"))
Export(encoding, "consolecfg", require("foundation.encoding.consolecfg"))
Export(encoding, "cvarfile", require("foundation.encoding.cvarfile"))
Export(encoding, "gma", require("foundation.encoding.gma"))
