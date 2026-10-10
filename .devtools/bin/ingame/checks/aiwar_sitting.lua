-- ws_aiwar_sitting_enabled (features/aiwar/sv.lua): with the war on a
-- payload map, pushers sit on the cart; turning the convar off gets every
-- one off, and none sits again while it is off. Needs DrGBase (the server
-- root server_root.py builds mounts it).
-- args: { timeout = seconds to wait for a seated soldier }
local CONVAR = "ws_aiwar_sitting_enabled"
local START_TIMEOUT = 40
local SEATED_TIMEOUT = 240
local STAYS_OFF = 10

local function Seated(aiwar)
	local n = 0
	for _, entry in pairs(aiwar.soldiers) do
		if entry.soldier:IsSeated() then n = n + 1 end
	end
	return n
end

return function(t)
	if DrGBase == nil then return t:Skip("DrGBase is not loaded on this server") end
	RunConsoleCommand(CONVAR, "1")
	-- mp_aiwar_start loads the feature on a map that has not yet
	game.ConsoleCommand("mp_aiwar_start\n")
	local aiwar = t:WaitFor(START_TIMEOUT, function()
		local feature = t:Feature("aiwar")
		return feature and feature.war and feature
	end)
	t:Check("the war starts", aiwar ~= nil, "")
	if not aiwar then return end

	local seated, waited = t:WaitFor(t.args.timeout or SEATED_TIMEOUT, function()
		return Seated(aiwar) > 0 or nil
	end)
	t:Check("a pusher sits on the cart", seated ~= nil, string.format("after %.1f s", waited))
	if not seated then return end
	t:Info("seated_before", Seated(aiwar))

	RunConsoleCommand(CONVAR, "0")
	t:Wait(1)
	t:Check("turning sitting off gets every soldier off the cart", Seated(aiwar) == 0, tostring(Seated(aiwar)))
	local sat = t:WaitFor(STAYS_OFF, function() return Seated(aiwar) > 0 or nil end)
	t:Check("none sits again while sitting is off", sat == nil, tostring(Seated(aiwar)))
	RunConsoleCommand(CONVAR, "1")
end
