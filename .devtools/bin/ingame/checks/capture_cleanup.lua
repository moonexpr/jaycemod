-- A map cleanup outside a round reset (game.CleanUpMap: an admin's cleanup,
-- or any path that skips RoundSpawn) recreates every team_control_point;
-- the capture set must hold the new entities, or the spectator's
-- observer-point descriptor indexes a missing point (capture.lua's Owner).
local POINT_CLASS = "team_control_point"
local SETTLE = 1

return function(t)
	local capture = t:Feature("capture")
	if not capture then return t:Skip("capture not loaded") end
	if not ents.FindByClass(POINT_CLASS)[1] then return t:Skip("the map has no " .. POINT_CLASS) end
	game.CleanUpMap()
	t:Wait(SETTLE)

	local points = ents.FindByClass(POINT_CLASS)
	local missing = {}
	for _, point in ipairs(points) do
		if not capture:Set():Has(point) then missing[#missing + 1] = tostring(point) end
	end
	t:Check("every " .. POINT_CLASS .. " is in the capture set after a cleanup", #missing == 0,
		string.format("%d of %d missing: %s", #missing, #points, table.concat(missing, ", ")))

	for _, observer in ipairs(ents.FindByClass("info_observer_point")) do
		local point = observer:AssociatedEntity()
		if IsValid(point) and point:GetClass() == POINT_CLASS then
			local ok, owner = pcall(capture.Owner, capture, point)
			t:Check("the owner of " .. tostring(point) .. " (an observer point's) is known", ok and owner ~= nil,
				tostring(owner))
		end
	end
end
