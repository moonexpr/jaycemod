-- The tactics engine: the strategy soldiers are organised by (a fire team's
-- doctrine, squads, lanes, posts, the setup zone, the hunt, the scenarios and
-- their monitors, the bot quota and the tuning of them all), each loaded the
-- first time it is read. NextSoldier's sibling: neither reads the other, but
-- for the bridge, which meets it. Its own addon, which the gamemode's loader
-- reads (shared_loader.lua's ADDON_TREES). One line a module, never a loop:
-- docs/foundation-game-split-plan.md.
local wartactics = Namespace ("wartactics")
Defer (wartactics, "monitors", "wartactics.monitors")
Defer (wartactics, "bridge", "wartactics.bridge")
Defer (wartactics, "scenario", "wartactics.scenario")
Defer (wartactics, "fireteam", "wartactics.fireteam")
Defer (wartactics, "tuning", "wartactics.tuning")
Defer (wartactics, "squad", "wartactics.squad")
Defer (wartactics, "mission", "wartactics.mission")
Defer (wartactics, "rooms", "wartactics.rooms")
Defer (wartactics, "incursion", "wartactics.incursion")
Defer (wartactics, "classes", "wartactics.classes")
Defer (wartactics, "ambush", "wartactics.ambush")
Defer (wartactics, "overwatch", "wartactics.overwatch")
Defer (wartactics, "room_hints", "wartactics.room_hints")
Defer (wartactics, "intel", "wartactics.intel")
Defer (wartactics, "lanes", "wartactics.lanes")
Defer (wartactics, "explore", "wartactics.explore")
Defer (wartactics, "hunt", "wartactics.hunt")
Defer (wartactics, "posts", "wartactics.posts")
Defer (wartactics, "zone", "wartactics.zone")
Defer (wartactics, "bot_quota", "wartactics.bot_quota")
-- On a server with native/nextsoldier, its twin is already here, which the native
-- ScenarioMonitor reads. No Twin line: the Lua one's module(...) builds at this path.
local scenarios = wartactics.scenarios
if scenarios and scenarios.UseRequire then
	scenarios.UseRequire (require)
else
	Defer (wartactics, "scenarios", "wartactics.scenarios")
end
Defer (wartactics, "hazards", "wartactics.hazards")
