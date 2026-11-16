-- features/capture/sv_points.lua's Rebuild: a point removed this frame is
-- still found by class until the frame ends, and is not taken into the set,
-- or the set would hold a NULL entity from then on (a built game stopping).
-- And what a point's own event (Sandcastle's control_point) means to the
-- mode: the notice and the win check, for the set's points alone.
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
	local controller = { hooks = {}, fired = {}, ran = {}, checked = 0 }
	local ws = setmetatable({
		Events = { Fire = function(name, fields) controller.fired[#controller.fired + 1] = { name = name, fields = fields } end },
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
		-- each point's own state, as its entity holds it
		control_point = setmetatable({
			Of = function(ent)
				local state = rawget(ent, "controlPoint") or control_point.New({ id = ent, printName = "the Bridge" })
				rawset(ent, "controlPoint", state)
				return state
			end,
		}, { __index = control_point }),
		hook = {
			Add = function(event, _, fn) controller.hooks[event] = fn end,
			Run = function(event) controller.ran[#controller.ran + 1] = event end,
		},
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
	-- the master's win check, counted
	function controller:CheckWinConditions() self.checked = self.checked + 1 end
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

T.test("a set's point changing owner is noticed, told and checked for the win; another's is not the set's", function()
	local point, stray = Point(false), Point(false)
	local controller = Controller({ point })
	controller:Rebuild()
	local e = controller.set:SetOwner(point, Teams.RED, control_point.CAUSE_CAPTURE, true, { "Ann" })[1]
	controller.hooks.ControlPointEvent(stray, e)
	T.eq(#controller.fired, 0, "a point not in the set")
	controller.hooks.ControlPointEvent(point, e)
	T.eq(controller.fired[1].name, "game_teamplay_point_captured", "the notice")
	T.eq(controller.fired[1].fields.cpname, "the Bridge", "naming the point")
	T.eq(controller.fired[1].fields.cappers[1], "Ann", "and its cappers")
	T.eq(controller.ran[1], "WSPointCaptured", "the mode's hook")
	T.eq(controller.checked, 1, "the win checked")
end)

T.test("a point's own unlock means nothing more to the mode", function()
	local point = Point(false)
	local controller = Controller({ point })
	controller:Rebuild()
	controller.hooks.ControlPointEvent(point, { kind = "unlocked", id = point })
	T.eq(#controller.fired, 0, "nothing told")
	T.eq(controller.checked, 0, "nothing checked")
end)

T.finish()
