-- foundation's caches, on the base cache class. One line a module, never a
-- loop: docs/foundation-game-split-plan.md.
local cache = Namespace("cache")
Twin(cache, "base", require("foundation.cache.base"))
Twin(cache, "lru", require("foundation.cache.lru"))
Twin(cache, "expiring", require("foundation.cache.expiring"))
Twin(cache, "memo", require("foundation.cache.memo"))
