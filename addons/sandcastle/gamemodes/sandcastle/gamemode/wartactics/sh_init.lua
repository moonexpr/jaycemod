-- The AI war's tactics engine: the strategy NextSoldier's soldiers are
-- organised by (a fire team's doctrine, squads, lanes, posts, the setup
-- zone, the hunt, the scenarios, the bot quota and the tuning of them all),
-- on NextSoldier and never under it, each loaded the first time it is
-- read. One line a module, never a loop: docs/foundation-game-split-plan.md.
local wartactics = Namespace("wartactics")
Defer(wartactics, "fireteam", "wartactics.fireteam")
Defer(wartactics, "tuning", "wartactics.tuning")
Defer(wartactics, "squad", "wartactics.squad")
Defer(wartactics, "lanes", "wartactics.lanes")
Defer(wartactics, "explore", "wartactics.explore")
Defer(wartactics, "hunt", "wartactics.hunt")
Defer(wartactics, "posts", "wartactics.posts")
Defer(wartactics, "zone", "wartactics.zone")
Defer(wartactics, "bot_quota", "wartactics.bot_quota")
Defer(wartactics, "scenarios", "wartactics.scenarios")
