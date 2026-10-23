-- When a soldier retreating to cover leaves it for a health kit
-- (features.aiwar.orders' FindHealth), after TF2's CTFBotGetHealth
-- (tf_bot_get_health.cpp):
--   urgency u = 1 - clamp((health - CRITICAL) / (OK - CRITICAL), 0, 1),
--     1 on fire: 0 at TF2's ok health, 1 at its critical health;
--   search range R = NEAR_RANGE + u * (FAR_RANGE - NEAR_RANGE): the more
--     hurt, the farther it goes, as TF2's;
--   safety s = max(the threat's distance from THREAT_NEAR (0) to THREAT_FAR
--     (1), the time since its last enemy over QUIET_TIME), clamped to 0..1,
--     1 with no known threat: how far the enemy has drawn off;
--   it leaves when u + s >= 1, for the nearest kit within R: near death it
--     goes whatever the danger, barely hurt only once safe.
local min, max = math.min, math.max
local ipairs = ipairs
local Geometry = require("foundation.math.geometry")
module(...)

CRITICAL, OK = 0.3, 0.8 -- tf_bot_health_critical_ratio, tf_bot_health_ok_ratio
NEAR_RANGE, FAR_RANGE = 1000, 2000 -- tf_bot_health_search_near_range, _far_range
THREAT_NEAR, THREAT_FAR = 500, 1500
QUIET_TIME = 5

local function Clamp01(x) return min(1, max(0, x)) end

function Urgency(healthShare, burning)
	if burning then return 1 end
	return 1 - Clamp01((healthShare - CRITICAL) / (OK - CRITICAL))
end

function SearchRange(urgency)
	return NEAR_RANGE + urgency * (FAR_RANGE - NEAR_RANGE)
end

-- threatDistance: to the nearest known threat, or nil for none; quiet:
-- seconds since its last enemy.
function Safety(threatDistance, quiet)
	if threatDistance == nil then return 1 end
	local away = Clamp01((threatDistance - THREAT_NEAR) / (THREAT_FAR - THREAT_NEAR))
	return max(away, Clamp01(quiet / QUIET_TIME))
end

function Leaves(urgency, safety)
	return urgency + safety >= 1
end

-- The nearest of kits ({ pos }) to pos within range, or nil.
function PickKit(kits, pos, range)
	local best, bestRange
	for _, kit in ipairs(kits) do
		local d = Geometry.Distance(kit.pos, pos)
		if d <= range and (not bestRange or d < bestRange) then best, bestRange = kit, d end
	end
	return best
end
