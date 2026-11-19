-- nextsoldier.locomotion.path_cost: a NextBot's path cost as one native function, held to its
-- Lua twin (nextsoldier.locomotion.PricedInLua) move by move: the bound, the hull's clearance,
-- the mode's strategy, the base rule (walkable rise, sprint jumps, the class's extra, a link's
-- length). And what only the native does: no Lua asked where the clearance and the sprint
-- jumps are already known.
local T = dofile ("tests/harness.lua")
T.native ("nextsoldier")
local Native = nextsoldier.locomotion.path_cost
local Locomotion = nextsoldier.locomotion

assert (type (Native) == "table", "nextsoldier.locomotion.path_cost, published by the binary")

-- A vector as GMod's answers Distance.
local function Vec (x, y, z)
	return
	{
		x = x, y = y, z = z,
		Distance = function (self, other)
			local dx, dy, dz = self.x - other.x, self.y - other.y, self.z - other.z
			return math.sqrt (dx * dx + dy * dy + dz * dz)
		end
	}
end

-- Areas as the engine passes them: an id, a centre, the search's cost so far, and the rise to
-- each neighbour.
local function Area (id, x, soFar, rises)
	return
	{
		id = id,
		IsValid = function () return true end,
		GetID = function (self) return self.id end,
		GetCenter = function () return Vec (x, 0, 0) end,
		GetCostSoFar = function () return soFar end,
		ComputeAdjacentConnectionHeightChange = function (self, other) return (rises or {}) [other.id] or 0 end
	}
end

local function Ladder (length)
	return { IsValid = function () return true end, GetLength = function () return length end }
end

-- A hull's clearance: its memo tables and Area/Link, which fill them and count their calls.
local function Clearance (areaFits, linkFits)
	local clearance = { areas = {}, links = {}, asked = 0 }
	function clearance:Area (area)
		self.asked = self.asked + 1
		local fits = areaFits [area.id] ~= false
		self.areas [area.id] = fits
		return fits
	end
	function clearance:Link (from, to)
		self.asked = self.asked + 1
		local fits = not (linkFits [from.id] and linkFits [from.id] [to.id] == false)
		self.links [from.id] = self.links [from.id] or {}
		self.links [from.id] [to.id] = fits
		return fits
	end
	return clearance
end

-- The laid sprint jumps as nav_gaps' SprintLinks keeps them: links [from] [to] = true, from
-- "from>to" keys.
local function Sprints (laid)
	local links = {}
	for key in pairs (laid) do
		local a, b = key:match ("^(%d+)>(%d+)$")
		a, b = tonumber (a), tonumber (b)
		links [a] = links [a] or {}
		links [a] [b] = true
	end
	return links
end

local LIMITS = { jumpHeight = 64, deathDropHeight = 200 }

local function Spec (fields)
	local spec = { jumpHeight = LIMITS.jumpHeight, deathDropHeight = LIMITS.deathDropHeight }
	for key, value in pairs (fields or {}) do spec [key] = value end
	return spec
end

-- Both prices of one move, the native's first.
local function Both (spec, area, from, ladder, length)
	local native = Native.New (spec) (area, from, ladder, nil, length)
	local lua = Locomotion.PricedInLua (spec) (area, from, ladder, nil, length)
	return native, lua
end

local function Same (what, spec, area, from, ladder, length, expected)
	local native, lua = Both (spec, area, from, ladder, length)
	T.eq (native, lua, what .. ": the native as its Lua twin")
	if expected ~= nil then T.eq (native, expected, what) end
end

local A, B = Area (1, 0, 0), Area (2, 100, 50, { [3] = 80, [4] = -250 })
local C, D = Area (3, 150, 0), Area (4, 160, 0)

T.test ("the first area costs nothing", function ()
	Same ("no fromArea", Spec (), A, nil, nil, nil, 0)
end)

T.test ("the base rule: so far, plus the link's length, a step's or the centres'", function ()
	Same ("centres",                              Spec (), A, B, nil,          nil, 150)
	Same ("a step's length",                      Spec (), A, B, nil,          30,  80)
	Same ("a step of 0: the centres",             Spec (), A, B, nil,          0,   150)
	Same ("a ladder's length, its rise left out", Spec (), C, B, Ladder (120), nil, 170)
end)

T.test ("a rise past the jump or a drop past death is refused", function ()
	Same ("too high", Spec (), C, B, nil, nil, -1)
	Same ("too deep", Spec (), D, B, nil, nil, -1)
end)

T.test ("a route past the bound is refused", function ()
	Same ("past",  Spec ({ bound = 40 }), A, B, nil, nil, -1)
	Same ("at it", Spec ({ bound = 50 }), A, B, nil, nil, 150)
end)

T.test ("the hull's clearance refuses an area or a link it does not fit, a ladder no link", function ()
	Same ("area",     Spec ({ clearance = Clearance ({ [1] = false }, {}) }),           A, B, nil,         nil, -1)
	Same ("link",     Spec ({ clearance = Clearance ({}, { [2] = { [1] = false } }) }), A, B, nil,         nil, -1)
	Same ("fits",     Spec ({ clearance = Clearance ({}, {}) }),                        A, B, nil,         nil, 150)
	Same ("a ladder", Spec ({ clearance = Clearance ({}, { [2] = { [1] = false } }) }), A, B, Ladder (10), nil, 60)
end)

T.test ("the mode's strategy prices the move in place of the base rule, told the fit", function ()
	-- each Same asks it twice, the native's then the twin's; a nil told is still counted
	local told, asked = {}, 0
	local function Cost (area, from, ladder, elevator, length, fits)
		asked = asked + 1
		told [asked] = fits
		return from:GetCostSoFar () + 7
	end
	Same ("its price", Spec ({ cost = Cost }), C, B, nil, nil, 57)
	T.eq (told [1], nil, "no clearance: no verdict")
	Same ("told it fits", Spec ({ cost = Cost, clearance = Clearance ({}, {}) }), A, B, nil, nil, 57)
	T.eq (told [3], true)
	Same ("told it does not", Spec ({ cost = Cost, clearance = Clearance ({ [1] = false }, {}) }), A, B, nil, nil, 57)
	T.eq (told [5], false)
end)

T.test ("a laid sprint jump is taken only by a bot that makes it", function ()
	local sprints = Sprints ({ ["2>1"] = { from = {}, to = {} } })
	Same ("none makes it", Spec ({ sprints = sprints }),                                            A, B, nil, nil, -1)
	Same ("it does",       Spec ({ sprints = sprints, sprintJump = function () return true end }),  A, B, nil, nil, 150)
	Same ("it does not",   Spec ({ sprints = sprints, sprintJump = function () return false end }), A, B, nil, nil, -1)
	Same ("no jump laid",  Spec ({ sprints = Sprints ({}) }),                                       A, B, nil, nil, 150)
end)

T.test ("the class adds to a move, or refuses it below 0", function ()
	Same ("adds",    Spec ({ extra = function () return 25 end }),  A, B, nil, nil, 175)
	Same ("refuses", Spec ({ extra = function () return -1 end }),  A, B, nil, nil, -1)
	Same ("nothing", Spec ({ extra = function () return nil end }), A, B, nil, nil, 150)
end)

T.test ("the native asks no Lua for a clearance already known", function ()
	local clearance = Clearance ({}, {})
	local cost = Native.New (Spec ({ clearance = clearance }))
	T.eq (cost (A, B), 150)
	T.eq (clearance.asked, 2, "the area and the link, asked once")
	T.eq (cost (A, B), 150)
	T.eq (clearance.asked, 2, "then read from its memo")
end)

T.test ("the native asks a bot once a link whether it makes a sprint jump", function ()
	local asked = 0
	local spec = Spec (
		{
			sprints = Sprints ({ ["2>1"] = {} }),
			sprintJump = function () asked = asked + 1 return true end
		}
	)
	local cost = Native.New (spec)
	cost (A, B)
	cost (A, B)
	T.eq (asked, 1)
end)

T.test ("the twin asks a bot once a link across its searches, its verdicts kept (sprintTold)", function ()
	local asked, told = 0, {}
	local function Spec_ ()
		return Spec (
			{
				sprints = Sprints ({ ["2>1"] = {} }),
				sprintJump = function () asked = asked + 1 return true end,
				sprintTold = told
			}
		)
	end
	T.eq (Locomotion.PricedInLua (Spec_ ()) (A, B), 150)
	T.eq (Locomotion.PricedInLua (Spec_ ()) (A, B), 150, "a second search")
	T.eq (asked, 1)
	T.eq (told [2] [1], true, "kept")
end)

T.test ("a search prices at most spec.links links: past them each is refused", function ()
	for _, make in ipairs ({ Native.New, Locomotion.PricedInLua }) do
		local cost = make (Spec ({ links = 2 }))
		T.eq (cost (A, nil), 0, "the first area is no link")
		T.eq (cost (A, B), 150)
		T.eq (cost (A, B), 150)
		T.eq (cost (A, B), -1, "the third link")
	end
	Same ("no limit", Spec (), A, B, nil, nil, 150)
end)

T.test ("a spec it cannot price is refused, naming the field", function ()
	local ok, why = pcall (Native.New, {})
	T.eq (ok, false)
	T.eq (tostring (why):find ("jumpHeight", 1, true) ~= nil, true, tostring (why))
	ok, why = pcall (Native.New, Spec ({ cost = 3 }))
	T.eq (tostring (why):find ("spec.cost is a function", 1, true) ~= nil, true, tostring (why))
	ok, why = pcall (Native.New, Spec ({ bound = "far" }))
	T.eq (tostring (why):find ("spec.bound is a number", 1, true) ~= nil, true, tostring (why))
end)

T.finish ()
