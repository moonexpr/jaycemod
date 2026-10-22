-- foundation's caches, on the base cache class. One line a module, never a
-- loop: docs/foundation-game-split-plan.md.
local cache = Namespace("cache")
Export(cache, "base", require("foundation.cache.base"))
Export(cache, "lru", require("foundation.cache.lru"))
Export(cache, "expiring", require("foundation.cache.expiring"))
Export(cache, "memo", require("foundation.cache.memo"))
