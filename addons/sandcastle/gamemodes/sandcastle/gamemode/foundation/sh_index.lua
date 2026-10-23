-- foundation's modules at its root, each a plain global. One line a
-- module, never a loop: docs/foundation-game-split-plan.md.
Export(_G, "transaction", require("foundation.transaction"))
Export(_G, "configstore", require("foundation.configstore"))
Export(_G, "nodegraph", require("foundation.nodegraph"))
