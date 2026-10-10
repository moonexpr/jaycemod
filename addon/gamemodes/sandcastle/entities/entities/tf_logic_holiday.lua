-- tf_logic_holiday (CTFHolidayEntity): the map's holiday, bound to the
-- holiday controller. Its keyvalues give the map's holiday; its input
-- HalloweenSetUsingSpells turns spells on or off. Halloween2013TeleportToHell
-- (Hell and its minigames) is left out: it logs once per map and does
-- nothing.
ENT.Type = "point"
ENT.Base = "base_point"

local HELL_MESSAGE = "tf_logic_holiday: Halloween2013TeleportToHell is not supported; ignored"
local loggedHell = false

-- FIELD_INTEGER keyvalues and inputs read as atoi does: a non-number is 0.
local ATOI_FALLBACK = 0

local function Int(value)
	return math.floor(tonumber(value) or ATOI_FALLBACK)
end

function ENT:KeyValue(key, value)
	self.kv = self.kv or {}
	self.kv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

-- CTFHolidayEntity's keyfields start at 0 (kHoliday_None).
function ENT:Initialize()
	local kv = self.kv or {}
	self.holiday = WS.Feature("holiday")
	self.holiday:BindHoliday(self, {
		holidayType = Int(kv.holiday_type),
		tauntInHell = Int(kv.tauntinhell) > 0,
		allowHaunting = Int(kv.allowhaunting) > 0,
	})
end

local INPUTS = {
	halloweensetusingspells = function(self, value)
		self.holiday:SetUsingSpells(Int(value) ~= 0)
	end,
	halloween2013teleporttohell = function()
		if loggedHell then return end
		loggedHell = true
		print(HELL_MESSAGE)
	end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
