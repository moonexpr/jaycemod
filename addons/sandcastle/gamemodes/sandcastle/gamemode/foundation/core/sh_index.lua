-- foundation's core namespace: classes, interfaces, constant sets and the
-- namespaces themselves (foundation.core.namespace runs this file). One line
-- a module, never a loop: docs/foundation-game-split-plan.md.
local core = Namespace("core")
Export(core, "class", require("foundation.core.class"))
Export(core, "port", require("foundation.core.port"))
Export(core, "constants", require("foundation.core.constants"))
Export(core, "enum", require("foundation.core.enum"))
Export(core, "namespace", require("foundation.core.namespace"))
