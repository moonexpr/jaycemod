-- The scenarios NextSoldier's soldiers play, which any script registers:
-- each with its activation criteria, its Scenario class (the Commander's:
-- features.aiwar.scenario's base) and, optionally, its own monitor, the
-- behaviour its soldiers' ScenarioMonitor runs in place of the doctrine's
-- sides (a nextsoldier.monitor, or any npc.nextbot Action). The war plays
-- the active scenario of highest priority, chosen again as the context
-- changes.
--
--   New() -> a registry; Shared is the one the war chooses from
--   registry:Register{ name, priority, active(context) -> truthy, scenario,
--     monitor? }: scenario is the Scenario class, or the module whose
--     Scenario is loaded the first time it is chosen (a map loads only its
--     own). A name registered again replaces its entry (a live reload).
--     A spec missing a part is refused, blamed on the caller
--   registry:Choose(context) -> the active entry of highest priority, a tie
--     to the name first; none active is refused. context = { mode (the
--     rounds mode's NAME, or nil), field (the war's field, nil before the
--     war starts) }: what the map's entities make, never the map's name
--   registry:Class(entry) -> its Scenario class
--   registry:Entries() -> the entries, highest priority first, then by name
local error, ipairs, require, setmetatable, sort, tostring, type =
	error, ipairs, require, setmetatable, table.sort, tostring, type
local Class = core.class
local Action = npc.nextbot.Action
module(...)

local Registry = {}
Registry.__index = Registry

function New()
	return setmetatable({ entries = {}, byName = {} }, Registry)
end

local function Check(ok, why)
	if not ok then error("a scenario spec " .. why, 3) end
end

local function Ordered(a, b)
	if a.priority ~= b.priority then return a.priority > b.priority end
	return a.name < b.name
end

function Registry:Register(spec)
	Check(type(spec) == "table", "is a table")
	Check(type(spec.name) == "string" and spec.name ~= "", "needs a name")
	Check(type(spec.priority) == "number", "needs a number priority")
	Check(type(spec.active) == "function", "needs active(context), its activation criteria")
	Check(type(spec.scenario) == "table" or type(spec.scenario) == "string", "needs its Scenario class or module")
	Check(spec.monitor == nil or Class.IsA(spec.monitor, Action), "gives a monitor that is a behaviour (an npc.nextbot Action)")
	local entry = {
		name = spec.name,
		priority = spec.priority,
		active = spec.active,
		scenario = spec.scenario,
		monitor = spec.monitor,
	}
	local old = self.byName[entry.name]
	if old then
		for i, e in ipairs(self.entries) do
			if e == old then self.entries[i] = entry end
		end
	else
		self.entries[#self.entries + 1] = entry
	end
	self.byName[entry.name] = entry
	sort(self.entries, Ordered)
	return entry
end

function Registry:Choose(context)
	for _, entry in ipairs(self.entries) do
		if entry.active(context) then return entry end
	end
	error("no scenario is active for mode " .. tostring(context.mode), 2)
end

-- A module named is required each time (require keeps it), so a module
-- loaded again, or put in place, is the one given.
function Registry:Class(entry)
	if type(entry.scenario) == "string" then return require(entry.scenario).Scenario end
	return entry.scenario
end

function Registry:Entries()
	local copy = {}
	for i, entry in ipairs(self.entries) do copy[i] = entry end
	return copy
end

Shared = Shared or New()
