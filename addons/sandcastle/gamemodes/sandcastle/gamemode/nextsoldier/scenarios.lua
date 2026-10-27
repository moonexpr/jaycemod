-- The scenarios NextSoldier's soldiers play, which any script registers:
-- each with its activation criteria, its Scenario class (the Commander's:
-- features.aiwar.scenario's base) and, optionally, its own monitor, the
-- behaviour its soldiers' ScenarioMonitor runs in place of the doctrine's
-- sides (a nextsoldier.monitor, or any npc.nextbot Action).
--
-- Registering is open while the game loads. At the game's beginning
-- Compile() makes the structure a decision reads mid-game: immutable, its
-- entries in priority order and indexed by the rounds mode they are for,
-- so a choice asks only the scenarios of the context's mode and those of
-- any mode. A registration after it reaches the next compile, not this one.
--
--   New() -> a registry; Shared is the one the war compiles
--   registry:Register{ name, priority, mode?, active?(context) -> truthy,
--     scenario, monitor? }: mode, the rounds mode's NAME it is for (none:
--     any mode); active, any criteria beyond the mode (none: always);
--     scenario, the Scenario class or the module whose Scenario is required
--     when chosen (a map loads only its own). A name registered again
--     replaces its entry (a live reload). A spec missing a part is refused,
--     blamed on the caller
--   registry:Compile() -> compiled:
--     compiled:Choose(context) -> the active entry of highest priority, a
--       tie to the name first; none active is refused. context = { mode
--       (the rounds mode's NAME, or nil), field (the war's field, nil
--       before the war starts) }: what the map's entities make, never the
--       map's name
--     compiled:Class(entry) -> its Scenario class
--     compiled:Entries() -> the entries, highest priority first, then by name
--   Compiled entries and the compiled structure refuse any change.
local error, ipairs, pairs, require, setmetatable, sort, tostring, type =
	error, ipairs, pairs, require, setmetatable, table.sort, tostring, type
local Class = core.class
local Action = npc.nextbot.Action
module(...)

local Registry = {}
Registry.__index = Registry

function New()
	return setmetatable({ specs = {} }, Registry)
end

local function Check(ok, why)
	if not ok then error("a scenario spec " .. why, 3) end
end

function Registry:Register(spec)
	Check(type(spec) == "table", "is a table")
	Check(type(spec.name) == "string" and spec.name ~= "", "needs a name")
	Check(type(spec.priority) == "number", "needs a number priority")
	Check(spec.mode == nil or type(spec.mode) == "string", "names its mode by the rounds mode's NAME")
	Check(spec.active == nil or type(spec.active) == "function", "gives its further criteria as active(context)")
	Check(type(spec.scenario) == "table" or type(spec.scenario) == "string", "needs its Scenario class or module")
	Check(spec.monitor == nil or Class.IsA(spec.monitor, Action), "gives a monitor that is a behaviour (an npc.nextbot Action)")
	self.specs[spec.name] = {
		name = spec.name,
		priority = spec.priority,
		mode = spec.mode,
		active = spec.active,
		scenario = spec.scenario,
		monitor = spec.monitor,
	}
end

-- A read-only view of data: a key set on it is refused, naming what.
local function Frozen(data, what)
	return setmetatable({}, {
		__index = data,
		__newindex = function(_, key) error(what .. " is compiled: " .. tostring(key) .. " cannot be set", 2) end,
		__metatable = what,
	})
end

local function Ordered(a, b)
	if a.priority ~= b.priority then return a.priority > b.priority end
	return a.name < b.name
end

local Compiled = {}
Compiled.__index = Compiled

function Registry:Compile()
	local order = {}
	for _, spec in pairs(self.specs) do order[#order + 1] = spec end
	sort(order, Ordered)
	local entries, anyMode, byMode = {}, {}, {}
	for i, spec in ipairs(order) do
		entries[i] = Frozen(spec, "scenario " .. spec.name)
		if spec.mode then byMode[spec.mode] = byMode[spec.mode] or {} end
	end
	-- each mode's list: its own entries and those of any mode, in order
	for i, spec in ipairs(order) do
		if spec.mode == nil then
			anyMode[#anyMode + 1] = entries[i]
			for _, list in pairs(byMode) do list[#list + 1] = entries[i] end
		else
			local list = byMode[spec.mode]
			list[#list + 1] = entries[i]
		end
	end
	return Frozen(setmetatable({ entries = entries, anyMode = anyMode, byMode = byMode }, Compiled), "the compiled scenarios")
end

function Compiled:Choose(context)
	local candidates = self.byMode[context.mode] or self.anyMode
	for i = 1, #candidates do
		local entry = candidates[i]
		local active = entry.active
		if active == nil or active(context) then return entry end
	end
	error("no scenario is active for mode " .. tostring(context.mode), 2)
end

-- A module named is required each time (require keeps it), so a module
-- loaded again, or put in place, is the one given.
function Compiled:Class(entry)
	local scenario = entry.scenario
	if type(scenario) == "string" then return require(scenario).Scenario end
	return scenario
end

function Compiled:Entries()
	local copy = {}
	for i, entry in ipairs(self.entries) do copy[i] = entry end
	return copy
end

Shared = Shared or New()
