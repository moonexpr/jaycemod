-- foundation's modules at its root, each a plain global. The other files
-- here are gameplay, bound for game/ and loaded on demand until then. One
-- line a module, never a loop: docs/foundation-game-split-plan.md.
Export(_G, "transaction", require("foundation.transaction"))
