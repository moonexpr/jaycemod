-- The capture controller's root, features/capture/sv.lua, loaded once in a
-- fake GMod: its top level runs, and what it wires (hooks, console
-- commands, convar callbacks, timers, event listeners) is recorded by
-- T.Wiring, as are the features it asks WS.Feature for. The recorded keys
-- and features are the controller's wiring as it stands; a reorganisation
-- of the file must leave them exactly as they are.
--
-- The fake: the wiring tables come from T.Wiring; WS.Feature records the
-- name it is asked for and answers an inert feature; every other engine
-- global the file reads, and every WS function but require, is an inert
-- stub, a table any field of which is the stub and any call of which
-- returns it, so the top level runs and nothing it defers (timer.Simple)
-- ever does.
local T = dofile("tests/harness.lua")

local SOURCE = T.ROOT .. "features/capture/sv.lua"

-- the wiring of features/capture/sv.lua, sorted
local WIRING = {
	"cvars tf_caplinear ws_capture",
	"hook AcceptInput ws_capture_point",
	"hook PostCleanupMap ws_capture",
	"hook Think ws_capture",
}

-- the features features/capture/sv.lua asks WS.Feature for, in order
local FEATURES = {
	"rounds",
}

local Inert = setmetatable({}, {
	__index = function(stub) return stub end,
	__call = function(stub) return stub end,
})

local function Load()
	local wiring = T.Wiring()
	local features = {} -- the names WS.Feature is asked for, in order
	local deferred = {} -- timer.Simple's functions, kept and never run
	local ws = setmetatable({
		require = T.require,
		FeatureParts = T.FeatureParts,
		Events = wiring.Events,
		Feature = function(name)
			features[#features + 1] = name
			return Inert
		end,
	}, { __index = function() return Inert end })
	local env = setmetatable({
		WS = ws,
		hook = wiring.hook,
		concommand = wiring.concommand,
		cvars = wiring.cvars,
		timer = {
			Create = wiring.timer.Create,
			Simple = function(_, fn) deferred[#deferred + 1] = fn end,
		},
	}, {
		__index = function(_, name)
			local value = _G[name]
			if value == nil then return Inert end
			return value
		end,
	})
	local controller = setfenv(assert(loadfile(SOURCE)), env)()
	return controller, wiring, features
end

local controller, wiring, features = Load()

T.test("the root returns a table", function()
	T.eq(type(controller), "table", "the controller")
end)

T.test("no wiring key is registered twice", function()
	local duplicates = wiring:Duplicates()
	T.eq(#duplicates, 0, "duplicates (" .. table.concat(duplicates, ", ") .. ")")
end)

T.test("the wiring keys are the baseline's", function()
	local keys = wiring:Registered()
	table.sort(keys)
	local actual, expected = table.concat(keys, "\n"), table.concat(WIRING, "\n")
	T.eq(actual, expected, "the sorted wiring keys")
end)

T.test("the features asked for are the baseline's", function()
	local actual, expected = table.concat(features, "\n"), table.concat(FEATURES, "\n")
	T.eq(actual, expected, "the WS.Feature names, in order")
end)

T.finish()
