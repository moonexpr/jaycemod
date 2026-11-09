-- What the hostage HUD shows (features/hostage/cl.lua draws it): TF2
-- Classified's VIP track (resource/ui/hudobjectivevip.res: its home on the
-- left, the getaway car on the right) with a Civilian's marker for each
-- hostage, as far along as it has come from where it was held toward the
-- rescue zone, tinted by its state: held, following a rescuer, rescued (at
-- the car), or killed (where it fell). Under it, the tally: rescued of all.
local ipairs, sort, tostring = ipairs, table.sort, tostring
local Scalar = math.scalar
local Geometry = math.geometry
local Rescue = require("features.hostage.model")
module(...)

HELD, FOLLOWING, RESCUED, KILLED = "held", "following", "rescued", "killed"

local TINTS = {
	[Rescue.HELD] = HELD,
	[Rescue.FOLLOWING] = FOLLOWING,
	[Rescue.RESCUED] = RESCUED,
	[Rescue.KILLED] = KILLED,
}

-- How far along a hostage at pos is from home toward zone: 0 at home (or
-- farther), 1 at the zone; a home in the zone is there already.
function Progress(pos, home, zone)
	local whole = Geometry.Distance2D(home, zone)
	if whole <= 0 then return 1 end
	return Scalar.Saturate(1 - Geometry.Distance2D(pos, zone) / whole)
end

-- hostages: { state, progress }s. Their markers { at (0..1), tint }, the
-- furthest along last.
function Markers(hostages)
	local markers = {}
	for i, h in ipairs(hostages) do
		markers[i] = { at = h.state == Rescue.RESCUED and 1 or h.progress, tint = TINTS[h.state] }
	end
	sort(markers, function(a, b) return a.at < b.at end)
	return markers
end

function Tally(hostages)
	local rescued = 0
	for _, h in ipairs(hostages) do
		if h.state == Rescue.RESCUED then rescued = rescued + 1 end
	end
	return tostring(rescued) .. "/" .. tostring(#hostages)
end
