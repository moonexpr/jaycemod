-- NextSoldier's base interface (nextsoldier.base): NextSoldier's base and
-- each class on it has every method the base requires, and each optional
-- component whole or not at all. An entity of each class is created
-- unspawned, checked and removed.
local CLASSES = { "base_nextsoldier", "npc_nextsoldier", "npc_path_probe" }

return function(t)
	local Base = nextsoldier.base
	for _, class in ipairs(CLASSES) do
		local ent = ents.Create(class)
		t:Check(class .. " is created", IsValid(ent), "")
		if IsValid(ent) then
			local ok, err = pcall(Base.METHODS.Check, Base.METHODS, ent)
			t:Check(class .. " has the base's methods", ok, ok and "" or tostring(err))
			for _, component in ipairs(Base.COMPONENTS) do
				if component.optional then
					local whole, has = pcall(Base.Has, ent, component)
					t:Check(class .. " has " .. component.name .. " whole or not at all", whole,
						whole and (has and "has it" or "has none") or tostring(has))
				end
			end
			ent:Remove()
		end
	end
end
