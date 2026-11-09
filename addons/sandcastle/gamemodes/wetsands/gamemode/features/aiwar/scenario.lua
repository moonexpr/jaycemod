-- The AI war's scenarios: each variant is a part,
-- features.aiwar.scenario.<mode>, on wartactics.scenario's class, required on
-- first use so a map loads only its own. They register as any script's do
-- (wartactics.scenarios), which is all the war decides from.
local Scenarios = wartactics.scenarios
local Behaviors = nextsoldier.behavior.registry
module(...)

-- games.gameplay.rounds Mode NAMEs -> the variant's module; any other mode, or
-- none, is fought freeform (FREEFORM).
FREEFORM = "features.aiwar.scenario.freeform"
VARIANTS = {
	payload = "features.aiwar.scenario.payload",
	control_points = "features.aiwar.scenario.control_points",
	koth = "features.aiwar.scenario.koth",
	arena = "features.aiwar.scenario.arena",
	hostage = "features.aiwar.scenario.hostage",
	defuse = "features.aiwar.scenario.defuse",
	ctf = "features.aiwar.scenario.ctf",
	deathmatch = "features.aiwar.scenario.deathmatch",
	mvm = "features.aiwar.scenario.mvm",
}

-- The war's own scenarios: each variant for its rounds mode, at
-- MODE_PRIORITY, required when chosen, and freeform, for any mode, below
-- them. A script's scenario at a higher priority, with its own criteria,
-- takes over where those hold.
local FREEFORM_PRIORITY, MODE_PRIORITY = Scenarios.FREEFORM_PRIORITY, Scenarios.MODE_PRIORITY

Scenarios.Shared:Register({ name = "freeform", priority = FREEFORM_PRIORITY, scenario = FREEFORM })
Scenarios.Shared:Register({ name = "payload", priority = MODE_PRIORITY, mode = "payload", scenario = VARIANTS.payload })
Scenarios.Shared:Register({ name = "control_points", priority = MODE_PRIORITY, mode = "control_points", scenario = VARIANTS.control_points })
Scenarios.Shared:Register({ name = "koth", priority = MODE_PRIORITY, mode = "koth", scenario = VARIANTS.koth })
Scenarios.Shared:Register({ name = "arena", priority = MODE_PRIORITY, mode = "arena", scenario = VARIANTS.arena })
Scenarios.Shared:Register({ name = "ctf", priority = MODE_PRIORITY, mode = "ctf", scenario = VARIANTS.ctf })
Scenarios.Shared:Register({ name = "deathmatch", priority = MODE_PRIORITY, mode = "deathmatch", scenario = VARIANTS.deathmatch })
Scenarios.Shared:Register({ name = "mvm", priority = MODE_PRIORITY, mode = "mvm", scenario = VARIANTS.mvm })
Scenarios.Shared:Register({ name = "hostage", priority = MODE_PRIORITY, mode = "hostage", scenario = VARIANTS.hostage })
Scenarios.Shared:Register({ name = "defuse", priority = MODE_PRIORITY, mode = "defuse", scenario = VARIANTS.defuse })

-- The registered scenarios, compiled against NextSoldier's compiled
-- behaviours (each behaviour a scenario names must be among them): what the
-- war decides from, made when it starts.
function Compile(behaviors)
	return Scenarios.Shared:Compile(behaviors)
end

-- The scenario entry compiled plays in context ({ mode, field }: never the
-- map's name, as the map's entities choose), and its Scenario class.
function Entry(compiled, context)
	local entry = compiled:Choose(context)
	return entry, compiled:Class(entry)
end

-- The Scenario class for a rounds mode's NAME alone, from a fresh compile
-- (for a test or a report, not a think): freeform for a mode without a
-- standard objective, or no rounds at all, unless a registered scenario
-- takes over.
function For(modeName)
	local _, class = Entry(Compile(Behaviors.Shared:Compile()), { mode = modeName })
	return class
end
