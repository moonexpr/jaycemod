-- Spell pickups (docs/pass3-halloween.md §11, P1 spells): the map's
-- tf_spell_pickups exist and play their idle sequence, so the server's
-- cycle advances.
local PICKUP_TIMEOUT = 10
local SAMPLE = 1 -- seconds between two readings of the cycle

return function(t)
	local pickups = t:WaitFor(PICKUP_TIMEOUT, function()
		local found = ents.FindByClass("tf_spell_pickup")
		return #found > 0 and found
	end)
	t:Info("spells_enabled", GetConVar("tf_spells_enabled") and GetConVar("tf_spells_enabled"):GetString() or "no convar")
	t:Check("the map has tf_spell_pickups", pickups ~= nil, tostring(pickups and #pickups or 0))
	if not pickups then return end
	local before = {}
	for i, p in ipairs(pickups) do before[i] = p:GetCycle() end
	t:Wait(SAMPLE)
	local moving, samples = 0, {}
	for i, p in ipairs(pickups) do
		if IsValid(p) then
			local after = p:GetCycle()
			if after ~= before[i] then moving = moving + 1 end
			samples[#samples + 1] = string.format("%s %.2f->%.2f", p:GetModel() or "?", before[i], after)
		end
	end
	t:Info("cycles", samples)
	t:Check("every pickup's cycle advances", moving == #pickups, moving .. " of " .. #pickups)
end
