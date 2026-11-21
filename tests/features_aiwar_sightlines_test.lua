-- features.aiwar.sightlines: how far a soldier sees from where it stands, measured once a place.
local T = dofile ("tests/harness.lua")
local Sightlines = T.require ("features.aiwar.sightlines")

T.test ("its measure is tuned", function ()
	T.defined (Sightlines.RAYS,     "rays round a place")
	T.defined (Sightlines.QUANTILE, "the share of them its reach covers")
	T.defined (Sightlines.RANGE,    "the farthest it measures")
end)

T.test ("the rays go round evenly, once", function ()
	local yaws = Sightlines.Yaws (8)
	T.eq (#yaws, 8, "eight")
	for i = 2, #yaws do T.near (yaws [i] - yaws [i - 1], 45, 1e-9, "evenly") end
	T.eq (yaws [1] >= 0 and yaws [#yaws] < 360, true, "within one turn")
end)

-- Its reach is how far most of its view goes: a long line out of a window does not make a room
-- open, nor a pillar beside it make a field closed.
T.test ("a place's reach is what its quantile of rays reach within, whatever their order", function ()
	local distances = {}
	for i = 1, 20 do distances [i] = (i * 7) % 20 * 100 + 100 end
	local reach = Sightlines.Reach (distances)
	local within = 0
	for _, d in ipairs (distances) do
		if d <= reach then within = within + 1 end
	end
	T.eq (within >= Sightlines.QUANTILE * #distances,    true, "its share within")
	T.eq (within - 1 < Sightlines.QUANTILE * #distances, true, "and no further than it needs")
	T.eq (distances [1],                                 800,  "the rays left as given")
end)

T.test ("one long sightline does not open a closed place", function ()
	local closed = { 200, 200, 200, 200, 200, 200, 200, Sightlines.RANGE }
	T.eq (Sightlines.Reach (closed), 200, "a doorway out")
end)

T.test ("a place is measured the first time it is asked, and kept", function ()
	local measured = 0
	local places = Sightlines.New (function (place)
		measured = measured + 1
		return { place.size, place.size, place.size, place.size }
	end)
	local hall, yard = { size = 300 }, { size = 1800 }
	T.eq (places:Reach (1, hall), 300,  "the hall")
	T.eq (places:Reach (1, hall), 300,  "again")
	T.eq (places:Reach (2, yard), 1800, "the yard")
	T.eq (measured,               2,    "each once")
end)

T.finish ()
