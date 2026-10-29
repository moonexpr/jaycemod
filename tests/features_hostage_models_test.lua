-- The hostages' models (features.hostage.models) and what the feature
-- preloads (features/hostage/resources.lua): the same models, each a path
-- under models/ that ends in .mdl, none named twice.
local T = dofile("tests/harness.lua")
local Models = T.require("features.hostage.models")
local resources = assert(loadfile(T.ROOT .. "features/hostage/resources.lua"))()

local function Sorted(list)
	local copy = {}
	for i, path in ipairs(list) do copy[i] = path end
	table.sort(copy)
	return copy
end

T.test("every model is a lower-case .mdl path under models/", function()
	T.eq(#Models.All(), #Models.MALE + #Models.FEMALE, "the two lists make up the whole")
	for _, path in ipairs(Models.All()) do
		T.eq(path:match("^models/[%l%d_/]+%.mdl$") ~= nil, true, path)
	end
end)

T.test("no model is named twice", function()
	local seen = {}
	for _, path in ipairs(Models.All()) do
		T.eq(seen[path], nil, path .. " twice")
		seen[path] = true
	end
end)

T.test("a hostage's look is drawn from all models by a number the caller gives", function()
	local all = Models.All()
	T.eq(Models.Pick(1), all[1], "the first")
	T.eq(Models.Pick(#all), all[#all], "the last")
	T.eq(Models.Pick(#all + 1), all[1], "it wraps")
end)

T.test("the feature preloads exactly its models", function()
	local names = Sorted(resources.models)
	local expected = Sorted(Models.All())
	T.eq(#names, #expected, "how many")
	for i = 1, #names do T.eq(names[i], expected[i], "model " .. i) end
end)

T.finish()
