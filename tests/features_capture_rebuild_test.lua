-- features/capture/sv_points.lua's Rebuild: a point removed this frame is
-- still found by class until the frame ends, and is not taken into the set,
-- or the set would hold a NULL entity from then on (a built game stopping).
local T = dofile("tests/harness.lua")
local Teams = gameplay.teams

local Inert = setmetatable({}, {
	__index = function(stub) return stub end,
	__call = function(stub) return stub end,
})

local function Point(marked)
	return setmetatable({ IsMarkedForDeletion = function() return marked end }, { __index = Inert })
end

local function Controller(found)
	local controller = {}
	local ws = setmetatable({
		require = T.require,
		TEAM_UNASSIGNED = Teams.UNASSIGNED,
		TEAM_RED = Teams.RED,
		TEAM_BLUE = Teams.BLUE,
		KeyValues = function() return {} end,
		Proxy = function() return Inert, false end,
	}, { __index = function() return Inert end })
	local env = setmetatable({
		WS = ws,
		ents = { FindByClass = function() return found end, FindByName = function() return {} end },
		Vector = function() return Inert end,
	}, {
		__index = function(_, name)
			local value = _G[name]
			if value == nil then return Inert end
			return value
		end,
	})
	local caplinear = { GetBool = function() return true end }
	local function Team() return Teams.UNASSIGNED end
	setfenv(assert(loadfile(T.ROOT .. "features/capture/sv_points.lua")), env)(controller, Team, { Teams.RED, Teams.BLUE }, caplinear)
	return controller
end

T.test("a point being removed is left out of the set", function()
	local live, going = Point(false), Point(true)
	local controller = Controller({ going, live })
	controller:Rebuild()
	local ids = controller.set:Ids()
	T.eq(#ids, 1, "only the one staying")
	T.eq(ids[1], live, "the live point")
end)

T.test("every point being removed leaves the set empty", function()
	local controller = Controller({ Point(true), Point(true) })
	controller:Rebuild()
	T.eq(#controller.set:Ids(), 0, "no points")
end)

T.finish()
