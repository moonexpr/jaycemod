-- A walker's path cost that spreads bots over routes: CZombiePathCost's
-- preference term makes each bot favour different areas, and keeps its
-- choice for ten seconds so repaths follow the same route.
local cos, floor = math.cos, math.floor
local Ground = require("foundation.wetsands.path.ground")
module(...)

local ROUTE_PERIOD = 10 -- seconds a bot keeps its preferences
local PREFERENCE_SPREAD = 50

function Preference(entIndex, areaId, now)
	local timeMod = floor(now / ROUTE_PERIOD) + 1
	return 1 + PREFERENCE_SPREAD * (1 + cos(entIndex * areaId * timeMod))
end

-- The first area of a search has no from-area and no other fields, so it
-- is priced before the preference reads the area id.
function Cost(step, limits, bot)
	if not step.hasFrom then return 0 end
	return Ground.Weighted(step, limits, Preference(bot.entIndex, step.areaId, bot.now))
end
