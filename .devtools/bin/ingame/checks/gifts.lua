-- Halloween gifts (foundation.holiday.halloween's schedule): the holiday
-- controller holds the map's gift spawn locations and a schedule whose
-- first round is 7 to 12 minutes off. The check moves that round to now
-- (the schedule's own nextAt, as a test clock would) and the controller
-- then gives every player a tf_halloween_gift_pickup at one of the
-- locations.
local Halloween = WETSAND.require("foundation.holiday.halloween")
local SECONDS_PER_MINUTE = 60
local SPAWN_TIMEOUT = 3
local AT_LOCATION = 1 -- units

return function(t)
	local holiday = t:Feature("holiday")
	if not holiday then return t:Check("the holiday feature is loaded", false, "") end
	local locations, gifts = holiday.giftLocations, holiday.gifts
	t:Check("gift spawn locations reached the holiday controller", #locations > 0, #locations .. " locations")
	t:Check("Halloween gives a gift schedule", gifts ~= nil, tostring(gifts))
	if not gifts or #locations == 0 then return end
	local due = gifts.nextAt and gifts.nextAt - CurTime()
	t:Check("the first gift round is 7 to 12 minutes off", due ~= nil
		and due > 0 and due <= Halloween.GIFT_INTERVAL_MAX * SECONDS_PER_MINUTE,
		due and string.format("%.0f s", due) or "not scheduled")

	local players = #player.GetAll()
	gifts.nextAt = CurTime()
	local spawned = t:WaitFor(SPAWN_TIMEOUT, function()
		local found = ents.FindByClass("tf_halloween_gift_pickup")
		return #found >= players and found
	end)
	local found = spawned or ents.FindByClass("tf_halloween_gift_pickup")
	t:Check("a gift for every player", #found == players, #found .. " gifts, " .. players .. " players")
	local placed = 0
	for _, gift in ipairs(found) do
		for _, pos in ipairs(locations) do
			if gift:GetPos():Distance(pos) <= AT_LOCATION then
				placed = placed + 1
				break
			end
		end
	end
	t:Check("each gift stands on a gift spawn location", placed == #found, placed .. " of " .. #found)
	local next = gifts.nextAt - CurTime()
	t:Check("the next round is scheduled 7 to 12 minutes on", next >= Halloween.GIFT_INTERVAL_MIN * SECONDS_PER_MINUTE - 1
		and next <= Halloween.GIFT_INTERVAL_MAX * SECONDS_PER_MINUTE, string.format("%.0f s", next))
end
