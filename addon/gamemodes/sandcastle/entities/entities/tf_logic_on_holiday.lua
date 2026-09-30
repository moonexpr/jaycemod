-- tf_logic_on_holiday (CLogicOnHoliday, tf_logic_on_holiday.cpp): Fire
-- fires IsAprilFools, IsFullMoon, IsHalloween, IsSmissmas, IsTFBirthday and
-- IsValentines for each holiday that is on, or IsNothing. A binding to the
-- holiday controller, which answers which.
ENT.Type = "point"
ENT.Base = "base_point"

-- Its outputs are named Is*, not On*.
local OUTPUT_PREFIX = "Is"

function ENT:KeyValue(key, value)
	if string.sub(key, 1, #OUTPUT_PREFIX) == OUTPUT_PREFIX then self:StoreOutput(key, value) end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Initialize()
	self.holiday = WETSAND.Feature("holiday")
end

function ENT:AcceptInput(name, activator, caller, value)
	if string.lower(name) ~= "fire" then return false end
	for _, output in ipairs(self.holiday:OnHolidayOutputs()) do self:TriggerOutput(output, self) end
	return true
end
