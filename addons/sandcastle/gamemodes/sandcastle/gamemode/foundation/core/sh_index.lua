-- foundation's core namespace: classes, interfaces, constant sets and the
-- namespaces themselves (foundation.core.namespace runs this file). One line
-- a module, never a loop: docs/foundation-game-split-plan.md.
local core = Namespace("core")
Twin(core, "class", require("foundation.core.class"))
Twin(core, "port", require("foundation.core.port"))
Twin(core, "constants", require("foundation.core.constants"))
Twin(core, "enum", require("foundation.core.enum"))
Export(core, "namespace", require("foundation.core.namespace"))
