-- Whether this map may use the Gameplay tools (the game builder, loaded by
-- their first use): a scenario's map, holding an objective of its own, may
-- not. Decided once, from what the map itself created.
local Builder = WS.require("features.builder.model")

local function MapHolds(class)
	for _, ent in ipairs(ents.FindByClass(class)) do
		if ent:CreatedByMap() then return true end
	end
	return false
end

hook.Add("InitPostEntity", "ws_builder", function()
	SetGlobal2Bool("ws_builder_available", not Builder.IsScenarioMap(MapHolds))
end)
