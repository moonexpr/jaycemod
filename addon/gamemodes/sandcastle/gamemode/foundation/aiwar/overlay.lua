-- The soldier overlay's layout (ws_aiwar_debug): each soldier's box
-- belongs centred above its head, and none may cover another. Boxes are
-- placed in the order given (nearest soldier first, so the nearest stay
-- put); one that would overlap a box already placed moves up above it,
-- again until it overlaps none.
local ipairs = ipairs
module(...)

GAP = 4 -- pixels between boxes

local function Overlaps(a, b)
	return a.left < b.left + b.w + GAP and b.left < a.left + a.w + GAP
		and a.top < b.top + b.h + GAP and b.top < a.top + a.h + GAP
end

-- boxes: { x (centre), bottom, w, h }. Returns, in the same order,
-- { left, top, w, h, moved } with moved true when a box left its place.
function Layout(boxes)
	local placed = {}
	for i, box in ipairs(boxes) do
		local rect = { left = box.x - box.w / 2, top = box.bottom - box.h, w = box.w, h = box.h, moved = false }
		local moving = true
		while moving do
			moving = false
			for _, other in ipairs(placed) do
				if Overlaps(rect, other) then
					rect.top = other.top - rect.h - GAP
					rect.moved = true
					moving = true
				end
			end
		end
		placed[i] = rect
	end
	return placed
end
