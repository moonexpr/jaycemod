-- wartactics.scenario: the Scenario class a custom scenario extends, with
-- NextSoldier out of reach and no war's feature loaded: all it needs of a mode
-- is a war that answers Members and AssignStances.
local T = dofile ("tests/harness.lua")
nextsoldier = setmetatable ({}, { __index = function (_, key) error ("read nextsoldier." .. key, 2) end })
local Base = wartactics.scenario
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE

-- A variant whose stances the test sets, and a war that keeps what it is told.
local function Variant (entries)
	local class = Base.Scenario:Extend ("under test")
	function class:Brief (field, now) field.briefed = now end
	function class:Stances () return entries, "defense" end
	return class:New ()
end

local function War ()
	return
	{
		Members = function () return {} end,
		AssignStances = function (self, chosen, defense) self.chosen, self.defense = chosen, defense end
	}
end

T.test ("the class loads with no war's feature", function ()
	T.eq (package.loaded ["features.aiwar.scenario"], nil, "the war's scenarios")
	T.eq (package.loaded ["features.aiwar.model"], nil, "the war's model")
end)

T.test ("a variant inherits what it does not override", function ()
	local variant = Base.Scenario:Extend ("mine")
	T.eq (variant.NAME, "mine", "its name")
	T.eq (variant.SQUAD_SIZE, Base.Scenario.SQUAD_SIZE, "its squad size")
	T.eq (variant.SQUAD_SIZE, wartactics.squad.FIRE_TEAM_SIZE, "a fire team's")
	T.eq (variant:TeamSizes (3) [RED], 3, "as many a side")
end)

T.test ("what a variant must fill in is refused by name", function ()
	local ok, why = pcall (function () return Base.Scenario:Extend ("bare"):New ():Front ({}, RED) end)
	T.eq (ok, false, "refused")
	T.eq (tostring (why):find ("bare scenario: Front", 1, true) ~= nil, true, tostring (why))
end)

T.test ("a map lacks what its variant needs; a round brings what it awaits", function ()
	local class = Base.Scenario:Extend ("mine")
	class.NEEDS, class.AWAITS = { Base.BASES }, { Base.POINTS }
	local bases = { [RED] = {}, [BLUE] = {} }
	T.eq (class:MapLacks ({}), Base.BASES, "no bases")
	T.eq (class:MapLacks ({ bases = bases }), nil, "the war may start")
	T.eq (class:Lacks ({ bases = bases }), Base.POINTS, "the round's points")
	T.eq (class:Lacks ({ bases = bases, points = { {} } }), nil, "whole")
end)

T.test ("a stance changes once it has held, unless critical or the team has none", function ()
	local entry = { stance = "hold", key = "hold" }
	local variant = Variant ({ [RED] = entry })
	local war = War ()
	variant:Allocate (war, {}, 0)
	T.eq (war.chosen [RED], "hold", "none yet: at once")
	T.eq (war.defense, "defense", "the share goes with it")

	local other = { stance = "push", key = "push" }
	variant = Variant ({ [RED] = entry })
	variant:Allocate (war, {}, 0)
	function variant:Stances () return { [RED] = other } end
	variant:Allocate (war, {}, 1)
	T.eq (war.chosen [RED], nil, "waits")
	variant:Allocate (war, {}, 1 + Base.ALLOCATION_HOLD)
	T.eq (war.chosen [RED], "push", "has held")

	local critical = { stance = "run", key = "run", critical = true }
	function variant:Stances () return { [RED] = critical } end
	variant:Allocate (war, {}, 2 + Base.ALLOCATION_HOLD)
	T.eq (war.chosen [RED], "run", "critical skips the wait")
end)

T.test ("a tick keeps the exploration board, briefs, then allocates", function ()
	local variant = Variant ({})
	local war, field = War (), { waypoints = {} }
	variant:Command (war, field, 7)
	T.eq (field.explore ~= nil, true, "the board on the field")
	T.eq (field.briefed, 7, "briefed")
	T.eq (war.chosen ~= nil, true, "allocated")
end)

T.test ("a custom scenario registers with its class, above the war's own", function ()
	local registry = wartactics.scenarios.New ()
	local class = Base.Scenario:Extend ("mine")
	registry:Register ({ name = "mode", priority = wartactics.scenarios.MODE_PRIORITY, scenario = Base.Scenario })
	registry:Register ({ name = "mine", priority = wartactics.scenarios.MODE_PRIORITY + 1, scenario = class })
	local compiled = registry:Compile ({ Has = function () return true end })
	T.eq (compiled:Class (compiled:Choose ({})), class, "chosen")
end)

T.finish ()
