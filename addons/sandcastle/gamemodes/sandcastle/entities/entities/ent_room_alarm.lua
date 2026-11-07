-- ent_room_alarm: a room's alarm. The squad occupying the room raises it when its leader orders
-- the squad to stack up, a guard missing (npc_pathfollower's NSLegsSay); the map raises it with
-- Trigger and quiets it with Silence. Raised, it sounds its klaxon (keyvalue "sound", looping)
-- for "duration" seconds and fires OnAlarm; quieted, it stops and fires OnSilenced.
ENT.Type = "point"
ENT.Base = "base_point"

-- The klaxon, and how long it sounds, unless the map says.
local SOUND, DURATION = "ambient/alarms/alarm_citizen_loop1.wav", 20

function ENT:KeyValue(key, value)
	if string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	elseif key == "sound" then
		self.klaxon = value
	elseif key == "duration" then
		self.duration = tonumber(value)
	end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

-- Sounding its klaxon for its duration, and OnAlarm; raised again while sounding, nothing.
function ENT:Raise()
	if self.sounding then return end
	self.sounding = CreateSound(self, self.klaxon or SOUND)
	self.sounding:SetSoundLevel(100)
	self.sounding:Play()
	self:TriggerOutput("OnAlarm", self)
	timer.Create("ent_room_alarm_" .. self:EntIndex(), self.duration or DURATION, 1, function()
		if IsValid(self) then self:Silence() end
	end)
end

function ENT:Silence()
	if not self.sounding then return end
	self.sounding:Stop()
	self.sounding = nil
	timer.Remove("ent_room_alarm_" .. self:EntIndex())
	self:TriggerOutput("OnSilenced", self)
end

function ENT:OnRemove()
	if self.sounding then self.sounding:Stop() end
	timer.Remove("ent_room_alarm_" .. self:EntIndex())
end

local INPUTS = {
	trigger = function(self) self:Raise() end,
	silence = function(self) self:Silence() end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self)
	return true
end
