-- logic_script: a map's VScript. GMod has no VScript, so a script someone has
-- ported is played by its feature, and any other is accepted and does nothing.
ENT.Type = "point"
ENT.Base = "base_point"

-- A script's file -> the feature ported from it.
local PORTS = {
	["graveyard.nut"] = "graveyard",
}

function ENT:KeyValue(key, value)
	if string.lower(key) == "vscripts" then self.script = string.lower(value) end
end

function ENT:Initialize()
	local feature = PORTS[self.script]
	if feature then self.port = WS.Feature(feature) end
end

function ENT:AcceptInput(name, activator, caller, value)
	if string.lower(name) == "runscriptcode" and self.port then self.port:RunScriptCode(value) end
	return true
end
