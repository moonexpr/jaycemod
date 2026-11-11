local COMBINE = "Combine"
local RESISTENCE = "Resistence"
local TERRORIST = "Terrorist"
local COUNTER_TERRORISTS = "Counter-Terrorists"

local TERRORIST_MODELS =
{
	arctic = true,
	guerilla = true,
	leet = true,
	phoenix = true
}

local sorted = {}

local function CategoryOf (entry)
	local model = string.lower (entry.model or "")
	if model:match ("^models/player/combine_soldier[%w_]*%.mdl$") then return COMBINE end
	if model:match ("^models/player/group03m?/") then return RESISTENCE end
	if entry.category == "Counter-Strike" and model:match ("^models/player/[^/]+%.mdl$") then
		local name = model:match ("^models/player/([^/]+)%.mdl$")
		return TERRORIST_MODELS [name] and TERRORIST or COUNTER_TERRORISTS
	end
end

for name, entry in pairs (player_manager.GetAllPlayerModels ()) do
	local category = CategoryOf (entry)
	if category and entry.category ~= category then
		player_manager.AddValidModel (name, entry.model, entry.title, category)
	end
end

local function For (category)
	if type (category) ~= "string" then error ("player model category must be a string", 2) end

	local models = sorted [category]
	if models then return models end

	models = {}
	for _, entry in pairs (player_manager.GetAllPlayerModels ()) do
		if entry.category == category then models [#models + 1] = entry.model end
	end
	table.sort (models)
	sorted [category] = models
	return models
end

local function Pick (category, randomInt)
	local models = For (category)
	if #models == 0 then error ("player model category has no models: " .. tostring (category), 2) end

	randomInt = randomInt or math.random
	local index = randomInt (1, #models)
	if type (index) ~= "number" or index ~= math.floor (index) or index < 1 or index > #models then
		error ("player model random source returned an index outside the category", 2)
	end
	return models [index]
end

WS.PlayerModels =
{
	COMBINE = COMBINE,
	RESISTENCE = RESISTENCE,
	TERRORIST = TERRORIST,
	COUNTER_TERRORISTS = COUNTER_TERRORISTS,
	For = For,
	Pick = Pick
}
