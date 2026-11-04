-- The behaviours NextSoldier's soldiers run, which the mode hosting them
-- provides: NextSoldier owns the contract (nextsoldier.chart) and the
-- soldier, the mode owns the behaviours (the AI war's orders register
-- theirs, its monitors among them) and NextSoldier runs them by name. Each
-- is a state of NextSoldier's chart.
--
-- Registering is open while the game loads. At the game's beginning the
-- mode compiles the registry (the war, beside its scenarios), and a soldier
-- is given the compiled behaviours, all its behaviours read mid-game. A
-- registration after a compile reaches the next one, not that one.
--
--   New() -> a registry; Shared is the one the war registers in
--   registry:Register{ name, behavior }: behavior a state class of
--     NextSoldier's chart. A name registered again replaces its behaviour
--     (a live reload). A spec missing a part is refused, blamed on the caller
--   registry:Compile() -> compiled:
--     compiled:Get(name) -> the behaviour; an unknown name is refused,
--       naming it
--     compiled:Has(name), compiled:Names() (sorted)
--   The compiled structure refuses any change.
local error, ipairs, pairs, setmetatable, sort, tostring, type = error, ipairs, pairs, setmetatable, table.sort, tostring, type
local Class = core.class
local SoldierChart = nextsoldier.chart
module(...)

local Registry = {}
Registry.__index = Registry

function New()
	return setmetatable({ behaviors = {} }, Registry)
end

local function Check(ok, why)
	if not ok then error("a behaviour spec " .. why, 3) end
end

function Registry:Register(spec)
	Check(type(spec) == "table", "is a table")
	Check(type(spec.name) == "string" and spec.name ~= "", "needs a name")
	Check(type(spec.behavior) == "table" and Class.IsA(spec.behavior, SoldierChart.CHART.base),
		"gives a behaviour that is a state of NextSoldier's chart")
	self.behaviors[spec.name] = spec.behavior
end

local Compiled = {}
Compiled.__index = Compiled

function Registry:Compile()
	local behaviors, names = {}, {}
	for name, behavior in pairs(self.behaviors) do
		behaviors[name] = behavior
		names[#names + 1] = name
	end
	sort(names)
	local compiled = setmetatable({ behaviors = behaviors, names = names }, Compiled)
	return setmetatable({}, {
		__index = compiled,
		__newindex = function(_, key) error("the compiled behaviours are fixed: " .. tostring(key) .. " cannot be set", 2) end,
		__metatable = "the compiled behaviours",
	})
end

function Compiled:Get(name)
	local behavior = self.behaviors[name]
	if behavior == nil then error("no behaviour " .. tostring(name) .. " is registered", 2) end
	return behavior
end

function Compiled:Has(name)
	return self.behaviors[name] ~= nil
end

function Compiled:Names()
	local copy = {}
	for i, name in ipairs(self.names) do copy[i] = name end
	return copy
end

Shared = Shared or New()
