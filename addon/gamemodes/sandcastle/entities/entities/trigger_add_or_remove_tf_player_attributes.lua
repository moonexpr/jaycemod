-- trigger_add_or_remove_tf_player_attributes
-- (CTriggerAddOrRemoveTFPlayerAttributes): a trigger bound to the
-- attributes controller. Keyvalues attribute_name, value, duration and
-- add_or_remove, plus the trigger's StartDisabled and filtername. A player
-- who enters gets the attribute (or loses it, with add_or_remove 1); with a
-- duration of -1 it is taken back when they leave. Only the attributes
-- foundation.players.attributes supports have an effect; any other name
-- logs once per map and the trigger does nothing, as TF2 does with a name
-- its schema lacks.
ENT.Type = "brush"
ENT.Base = "wetsand_trigger_volume"

local UNSUPPORTED_MESSAGE = "trigger_add_or_remove_tf_player_attributes: attribute %q is not supported; ignored"
local logged = {}

-- Keyvalues read as atof does: a non-number is 0.
local ATOF_FALLBACK = 0

local function Float(value)
	return tonumber(value) or ATOF_FALLBACK
end

function ENT:TriggerInit()
	self.attributes = WETSAND.Feature("attributes")
	self.attribute = {
		name = self:Key("attribute_name", ""),
		value = Float(self:Key("value")),
		duration = Float(self:Key("duration")),
		remove = Float(self:Key("add_or_remove")) ~= 0,
	}
	local name = self.attribute.name
	self.valid = self.attributes:Supported(name)
	if not self.valid and name ~= "" and not logged[name] then
		logged[name] = true
		print(string.format(UNSUPPORTED_MESSAGE, name))
	end
end

function ENT:PlayerStartTouch(ply)
	if not self.valid or not self:PassesTriggerFilters(ply) then return end
	self.attributes:StartTouch(ply, self.attribute)
	self:TriggerOutput("OnStartTouch", ply)
end

-- CBaseTrigger::Disable ends touches after disabling, so a disabled
-- trigger takes nothing back.
function ENT:PlayerEndTouch(ply)
	if not self.enabled or not self.valid or not self:PassesTriggerFilters(ply) then return end
	self.attributes:EndTouch(ply, self.attribute)
end
