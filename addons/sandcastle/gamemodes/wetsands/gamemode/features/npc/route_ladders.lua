-- Nav ladders as the route searches take them (sv_routes.lua): which of an area's ladders are
-- links of the searches' mesh (wetsands.navsearch's Ladder), and the points a route walks to
-- climb one. The engine's objects stay with the controller; here are ids, lengths and
-- { x, y, z } positions.
--   Links(ladders, linked[, from]) -> { { to, length, handle } }: ladders is the area's, each
--     { to (the area id it reaches), length, handle (the caller's, kept) } in the engine's
--     order; one link an area reached, by its shortest ladder, in the order first met; none
--     to an area the floor already links (linked [id]), nor to the area itself (from).
--   Points(foot, head, out, up) -> the two points of a climb: up, from where a body stands
--     before the foot (STAND_OUT out from the ladder's face, along out, its normal) to the
--     head; down, from the head to before the foot.
local ipairs = ipairs
module (...)

-- A body stands this far out from a ladder's face to take it: about its own half width.
STAND_OUT = 24

function Links (ladders, linked, from)
	local links, at = {}, {}
	for _, ladder in ipairs (ladders) do
		local to = ladder.to
		if to ~= from and not linked [to] then
			local place = at [to]
			if not place then
				place = #links + 1
				at [to] = place
				links [place] = { to = to, length = ladder.length, handle = ladder.handle }
			elseif ladder.length < links [place].length then
				links [place] = { to = to, length = ladder.length, handle = ladder.handle }
			end
		end
	end
	return links
end

function Points (foot, head, out, up)
	local before = { x = foot.x + out.x * STAND_OUT, y = foot.y + out.y * STAND_OUT, z = foot.z }
	local top = { x = head.x, y = head.y, z = head.z }
	if up then return { before, top } end
	return { top, before }
end
