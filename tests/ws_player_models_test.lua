local T = dofile("tests/harness.lua")

local entries = {
	combine = { model = "models/player/combine_soldier.mdl", title = "Combine", category = "Half-Life 2" },
	combine_prison = { model = "models/player/combine_soldier_prisonguard.mdl", title = "Prison Guard", category = "Half-Life 2" },
	rebel = { model = "models/player/Group03/male_02.mdl", title = "Rebel", category = "Half-Life 2 - Citizens" },
	medic = { model = "models/player/Group03m/male_01.mdl", title = "Medic", category = "Half-Life 2 - Citizens" },
	arctic = { model = "models/player/arctic.mdl", title = "Arctic", category = "Counter-Strike" },
	leet = { model = "models/player/leet.mdl", title = "Leet", category = "Counter-Strike" },
	urban = { model = "models/player/urban.mdl", title = "Urban", category = "Counter-Strike" },
	hostage = { model = "models/player/hostage/hostage_01.mdl", title = "Hostage", category = "Counter-Strike" },
}

local playerManager = {
	GetAllPlayerModels = function()
		local copy = {}
		for name, entry in pairs(entries) do
			copy[name] = { model = entry.model, title = entry.title, category = entry.category }
		end
		return copy
	end,
	AddValidModel = function(name, model, title, category)
		entries[name] = { model = model, title = title, category = category }
	end,
}

local env = setmetatable({
	WS = {},
	player_manager = playerManager,
}, { __index = _G })
local chunk = assert(loadfile(T.ROOT .. "sh_player_models.lua"))
setfenv(chunk, env)
chunk()
local Models = env.WS.PlayerModels

T.test("existing models are registered under their Sandcastle side categories", function()
	T.eq(entries.combine.category, "Combine", "Combine")
	T.eq(entries.combine_prison.category, "Combine", "Combine prison guard")
	T.eq(entries.rebel.category, "Resistence", "Resistence")
	T.eq(entries.medic.category, "Resistence", "Resistence medic")
	T.eq(entries.arctic.category, "Terrorist", "Terrorist")
	T.eq(entries.leet.category, "Terrorist", "Terrorist")
	T.eq(entries.urban.category, "Counter-Terrorists", "Counter-Terrorists")
	T.eq(entries.hostage.category, "Counter-Strike", "hostage model keeps its category")
end)

T.test("category queries cache a sorted model list", function()
	local combine = Models.For(Models.COMBINE)
	T.eq(combine, Models.For(Models.COMBINE), "the category list is cached")
	T.eq(combine[1], "models/player/combine_soldier.mdl", "first Combine model")
	T.eq(combine[2], "models/player/combine_soldier_prisonguard.mdl", "second Combine model")

	local resistance = Models.For(Models.RESISTENCE)
	T.eq(resistance[1], "models/player/Group03/male_02.mdl", "sorted Resistance model")
	T.eq(resistance[2], "models/player/Group03m/male_01.mdl", "sorted Resistance medic model")
end)

T.test("the picker chooses from the category with the caller's random source", function()
	local picked = Models.Pick(Models.TERRORIST, function(low, high)
		T.eq(low, 1, "first index")
		T.eq(high, 2, "last index")
		return high
	end)
	T.eq(picked, "models/player/leet.mdl", "last sorted terrorist model")

	picked = Models.Pick(Models.COUNTER_TERRORISTS, function() return 1 end)
	T.eq(picked, "models/player/urban.mdl", "first counter-terrorist model")
	T.eq(pcall(Models.Pick, "Missing"), false, "an empty category cannot be picked")
	T.eq(pcall(Models.Pick, Models.TERRORIST, function() return 0 end), false, "bad random results are refused")
	T.eq(pcall(Models.For, nil), false, "a missing category is refused")
end)

T.finish()
