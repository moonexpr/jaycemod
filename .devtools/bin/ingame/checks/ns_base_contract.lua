-- NextSoldier's base interface (nextsoldier.base): each soldier class the
-- war fields has every method the base declares. Today the classes are
-- DrGBase's; once NextSoldier's own base replaces it, the same check holds
-- that one to the interface our code keeps. An entity of each class is
-- created unspawned, checked and removed.
local CLASSES = { "ws_drg_combine", "ws_drg_rebel", "ws_drg_vortigaunt" }

return function(t)
	local Base = nextsoldier.base
	for _, class in ipairs(CLASSES) do
		local ent = ents.Create(class)
		t:Check(class .. " is created", IsValid(ent), "")
		if IsValid(ent) then
			local ok, err = pcall(Base.METHODS.Check, Base.METHODS, ent)
			t:Check(class .. " has the base's methods", ok, ok and "" or tostring(err))
			ent:Remove()
		end
	end
end
