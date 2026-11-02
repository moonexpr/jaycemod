-- game's lists, in GMod's list table beside foundation's, each loaded the
-- first time it is read. One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local list = Namespace("list")
Defer(list, "drawlist", "games.list.drawlist")
