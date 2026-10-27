-- foundation's lists, queues and slot arrays, in GMod's list table. One
-- line a module, never a loop: docs/foundation-game-split-plan.md.
local list = Namespace("list")
Twin(list, "queue", require("foundation.list.queue"))
Twin(list, "ring", require("foundation.list.ring"))
Twin(list, "slots", require("foundation.list.slots"))
Twin(list, "chain", require("foundation.list.chain"))
Twin(list, "schedule", require("foundation.list.schedule"))
Twin(list, "select", require("foundation.list.select"))
