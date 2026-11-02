local T = dofile("tests/harness.lua")
local Profiles = T.require("features.aiwar.profiles")

T.test("the Combine and Resistance profiles use their player-model categories", function()
	T.eq(Profiles.ModelCategory("combine"), "Combine", "Combine")
	T.eq(Profiles.ModelCategory("rebel"), "Resistence", "Resistence")
end)

T.test("hostage and defuse sides use their Counter-Strike model categories", function()
	for _, mode in ipairs({ "hostage", "defuse" }) do
		T.eq(Profiles.ModelCategory("combine", mode, true), "Terrorist", mode .. " RED")
		T.eq(Profiles.ModelCategory("rebel", mode, false), "Counter-Terrorists", mode .. " BLU")
	end
end)

T.test("profiles without a player-model category keep their model", function()
	T.eq(Profiles.ModelCategory("vortigaunt"), nil, "vortigaunt")
end)

T.finish()
