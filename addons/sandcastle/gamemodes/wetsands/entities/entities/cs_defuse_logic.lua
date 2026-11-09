-- cs_defuse_logic: a map's bomb defusal settings, as keyvalues
-- (features.defuse.config): roundtime, c4timer, planttime, defusetime,
-- bombradius, CS:S's defaults where left out. The defuse controller reads the
-- map's first, and makes one with the defaults on a map without one.
ENT.Type = "point"

function ENT:KeyValue(key, value)
	self.wsKeyValues = self.wsKeyValues or {}
	self.wsKeyValues[string.lower(key)] = value
end

-- The settings, parsed once; mapRadius: the map's own bomb radius, or nil.
function ENT:Config(mapRadius)
	if not self.wsConfig then
		self.wsConfig = WS.require("features.defuse.config").Parse(self.wsKeyValues or {}, mapRadius)
	end
	return self.wsConfig
end
