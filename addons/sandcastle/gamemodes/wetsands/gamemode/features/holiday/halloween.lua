-- The Halloween holiday mode: the "you are IT" warnings, and a gift for
-- every player every 7 to 12 minutes (CTFGameRules::PeriodicHalloweenUpdate).
--
-- GiftSchedule(random) -> schedule, where random(lo, hi) draws an integer.
-- The holiday controller calls schedule:Tick(now, players, locations) as
-- often as it likes, with the registered tf_halloween_gift_spawn_location
-- origins, and spawns a tf_halloween_gift_pickup for each { player,
-- location } it returns, living LIFETIME seconds.
local require = require
local Holiday = require("features.holiday.model")
local ipairs, setmetatable = ipairs, setmetatable
module(...)

HOLIDAY = Holiday.HALLOWEEN
ANNOUNCES_IT = true
LIFETIME = 240 -- tf_halloween_gift_lifetime

GIFT_INTERVAL_MIN, GIFT_INTERVAL_MAX = 7, 12 -- minutes
local SECONDS_PER_MINUTE = 60

local Schedule = {}
Schedule.__index = Schedule

function GiftSchedule(random)
	return setmetatable({
		random = random,
		nextAt = nil,
	}, Schedule)
end

local function NextRound(self, now)
	self.nextAt = now + self.random(GIFT_INTERVAL_MIN, GIFT_INTERVAL_MAX) * SECONDS_PER_MINUTE
end

-- The clock starts at the first tick with a location; each round then gives
-- every player a gift at a random location.
function Schedule:Tick(now, players, locations)
	local gifts = {}
	if #locations == 0 then return gifts end
	if self.nextAt == nil then
		NextRound(self, now)
		return gifts
	end
	if now < self.nextAt then return gifts end
	NextRound(self, now)
	for i, player in ipairs(players) do
		gifts[i] = {
			player = player,
			location = locations[self.random(1, #locations)],
		}
	end
	return gifts
end
