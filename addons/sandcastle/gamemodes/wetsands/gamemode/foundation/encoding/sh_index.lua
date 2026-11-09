-- foundation's text and archive formats. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local encoding = Namespace("encoding")
Twin(encoding, "cursor", require("foundation.encoding.cursor"))
Twin(encoding, "utf16", require("foundation.encoding.utf16"))
Twin(encoding, "keyvalues", require("foundation.encoding.keyvalues"))
Twin(encoding, "consolecfg", require("foundation.encoding.consolecfg"))
Twin(encoding, "cvarfile", require("foundation.encoding.cvarfile"))
Twin(encoding, "gma", require("foundation.encoding.gma"))
