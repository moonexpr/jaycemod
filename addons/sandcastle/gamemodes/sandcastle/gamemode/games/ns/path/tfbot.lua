-- The path cost of TF2's bots and MvM's robots: CTFBotPathCost (tf_bot.h)
-- with CTFBotLocomotion::IsAreaTraversable's spawn-room rule. Besides a
-- step's usual fields it reads step.spawnRoomTeam (the team whose spawn room
-- the area lies in, UNASSIGNED for none: TF_NAV_SPAWN_ROOM_RED/_BLUE), and
-- the bot is { entIndex, now, team, route, miniBoss, roundWon, winningTeam }.
--
-- Left out, as nothing in Sandcastle feeds them: SAFEST_ROUTE's combat
-- intensity and sentry danger (no area combat tracking, no sentries), the
-- spy's building and teammate terms (no classes), training mode, and
-- func_nav_cost multipliers (the func_nav_* entities are no-ops here). A
-- safest or retreat route therefore costs as a fastest one. The default
-- route's preference is the skeletons' (games.ns.path.scatter) in
-- Lua's doubles, where TF2 takes FastCos of a float product: the same
-- spread over routes, not the same route as TF2 for a given bot and area.
local Path = require("games.ns.path")
local Scatter = require("games.ns.path.scatter")
module(...)

-- RouteType (nav_pathfind.h)
DEFAULT_ROUTE, FASTEST_ROUTE, SAFEST_ROUTE, RETREAT_ROUTE = 0, 1, 2, 3

local IMPASSABLE = Path.IMPASSABLE
local JUMP_PENALTY = 2 -- CTFBotPathCost's, where the zombie's is 5
local NOBODY = 0 -- TEAM_UNASSIGNED: the area is in no spawn room

local function Distance(step)
	if step.ladderLength then return step.ladderLength end
	if step.length > 0 then return step.length end
	return step.centerDistance
end

-- The enemy's spawn room is closed to a bot until the round is won, and then
-- open only to the winners (CTFBotLocomotion::IsAreaTraversable, and the
-- cost's own check, which the winners pass too).
local function InEnemySpawnRoom(step, bot)
	local room = step.spawnRoomTeam
	if room == NOBODY or room == bot.team then return false end
	return not (bot.roundWon and bot.winningTeam == bot.team)
end

local function Preference(step, bot)
	if bot.route ~= DEFAULT_ROUTE or bot.miniBoss then return 1 end
	return Scatter.Preference(bot.entIndex, step.areaId, bot.now)
end

function Cost(step, limits, bot)
	if not step.hasFrom then return 0 end
	if not step.traversable or InEnemySpawnRoom(step, bot) then return IMPASSABLE end
	local dist = Distance(step)
	local deltaZ = step.heightChange
	if not Path.Walkable(deltaZ, limits) then return IMPASSABLE end
	if deltaZ >= limits.stepHeight then dist = dist * JUMP_PENALTY end
	return dist * Preference(step, bot) + step.fromCostSoFar
end
