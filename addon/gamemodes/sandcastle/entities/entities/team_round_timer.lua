-- team_round_timer: the round clock (CTeamRoundTimer,
-- teamplay_round_timer.cpp), bound to the rounds feature, which holds its
-- foundation.rounds.timer model, thinks it, and fires its outputs here.
ENT.Type = "point"
ENT.Base = "base_point"

-- Keyvalue -> the Timer field it sets, as a number.
local NUMBER_KEYS = {
	timer_length = "length",
	max_length = "maxLength",
	setup_length = "setupLength",
}

-- Keyvalue -> the Timer flag it sets (nonzero is on).
local FLAG_KEYS = {
	start_paused = "startPaused",
	show_in_hud = "showInHud",
	auto_countdown = "autoCountdown",
	reset_time = "resetTime",
	startdisabled = "startDisabled",
}

-- CTeamRoundTimer's keyvalue defaults.
local function Defaults()
	return {
		length = 600,
		maxLength = 0,
		setupLength = 0,
		startPaused = true,
		showInHud = true,
		autoCountdown = true,
		resetTime = false,
		startDisabled = false,
	}
end

function ENT:KeyValue(key, value)
	self.kv = self.kv or Defaults()
	local k = string.lower(key)
	if NUMBER_KEYS[k] then
		self.kv[NUMBER_KEYS[k]] = tonumber(value) or 0
	elseif FLAG_KEYS[k] then
		self.kv[FLAG_KEYS[k]] = (tonumber(value) or 0) ~= 0
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	WETSAND.Feature("rounds"):BindTimer(self, self.kv or Defaults())
end

function ENT:OnRemove()
	WETSAND.Feature("rounds"):UnbindTimer(self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:AcceptInput(name, activator, caller, value)
	return WETSAND.Feature("rounds"):TimerInput(self, string.lower(name), value)
end

-- The same inputs for Lua callers.
function ENT:DoInput(name, value)
	WETSAND.Feature("rounds"):TimerInput(self, string.lower(name), value)
end
