-- foundation.aiwar.overlay: laying the soldier overlay's boxes out on the
-- screen so none covers another.
local T = dofile("tests/harness.lua")
local Overlay = T.require("foundation.aiwar.overlay")

local function Box(x, bottom, w, h) return { x = x, bottom = bottom, w = w, h = h } end

local function Overlaps(a, b)
	return a.left < b.left + b.w and b.left < a.left + a.w and a.top < b.top + b.h and b.top < a.top + a.h
end

T.test("a box alone sits centred on its anchor, above it", function()
	local placed = Overlay.Layout({ Box(100, 200, 40, 30) })
	T.eq(placed[1].left, 80, "centred")
	T.eq(placed[1].top, 170, "above the anchor")
	T.eq(placed[1].moved, false, "where it belongs")
end)

T.test("a box that would cover one placed before it moves up above it", function()
	local placed = Overlay.Layout({ Box(100, 200, 40, 30), Box(110, 205, 40, 30) })
	T.eq(Overlaps(placed[1], placed[2]), false, "apart")
	T.eq(placed[2].top, 170 - Overlay.GAP - 30, "just above the first")
	T.eq(placed[2].moved, true, "marked as moved")
	T.eq(placed[1].moved, false, "the first stays")
end)

T.test("a pile of boxes on one spot becomes a column with none overlapping", function()
	local boxes = {}
	for i = 1, 6 do boxes[i] = Box(300, 400, 120, 50 + i) end
	local placed = Overlay.Layout(boxes)
	for i = 1, #placed do
		for j = i + 1, #placed do T.eq(Overlaps(placed[i], placed[j]), false, i .. " and " .. j) end
	end
end)

T.test("boxes side by side stay where they are", function()
	local placed = Overlay.Layout({ Box(100, 200, 40, 30), Box(300, 200, 40, 30) })
	T.eq(placed[2].top, 170, "not moved")
end)

T.finish()
