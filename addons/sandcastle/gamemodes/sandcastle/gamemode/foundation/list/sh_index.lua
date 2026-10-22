-- foundation's lists, queues and slot arrays, in GMod's list table. One
-- line a module, never a loop: docs/foundation-game-split-plan.md.
local list = Namespace("list")
Export(list, "queue", require("foundation.list.queue"))
Export(list, "ring", require("foundation.list.ring"))
Export(list, "slots", require("foundation.list.slots"))
Export(list, "chain", require("foundation.list.chain"))
Export(list, "schedule", require("foundation.list.schedule"))
