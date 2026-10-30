-- cs_logic_hostage: a map's hostage settings, as keyvalues
-- (features.hostage.config): bodyclass, the class each hostage_entity spawns
-- as its hostage (npc_civilian when left out); bodymodel, the model it is
-- given (a prop needs one); and pistol, 1 for one hostage a round armed, 0
-- for none. The hostage controller reads the map's first,
-- and makes one with the defaults on a map without one (Controller:Config).
ENT.Type = "point"

function ENT:KeyValue(key, value)
	self.wsKeyValues = self.wsKeyValues or {}
	self.wsKeyValues[string.lower(key)] = value
end

-- The settings, parsed once (a value that is not one is refused, naming its key).
function ENT:Config()
	if not self.wsConfig then
		self.wsConfig = WS.require("features.hostage.config").Parse(self.wsKeyValues or {})
	end
	return self.wsConfig
end
