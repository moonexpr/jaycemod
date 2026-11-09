-- halloween_zapper (CTFHellZap): a binding to a features.hazards.zapper
-- model through the hazards controller. Keyvalues touch_trigger (a
-- dispenser_touch_trigger, found by name), ParticleEffect and ZapperType;
-- inputs Enable, Disable and ZapTouching (Kill and AddOutput are the
-- engine's). The trigger's volume is polled every tick, and players walking
-- in or out are the zapper's touches, as CDispenserTouchTrigger forwards
-- them to its owner.
ENT.Type = "point"
ENT.Base = "base_point"

local VARIANT = "features.hazards.zapper"

-- FIELD_INTEGER keyvalues read as atoi does: a non-number is 0.
local ATOI_FALLBACK = 0

local function Int(value)
	return math.floor(tonumber(value) or ATOI_FALLBACK)
end

function ENT:KeyValue(key, value)
	self.kv = self.kv or {}
	self.kv[string.lower(key)] = value
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

-- CTFHellZap::Spawn finds the trigger once; every map entity exists by now.
function ENT:Initialize()
	local kv = self.kv or {}
	self.hazards = WS.Feature("hazards")
	self.hazard = self.hazards:Bind(self, VARIANT, {
		type = Int(kv.zappertype),
		particle = kv.particleeffect,
	})
	if kv.particleeffect and kv.particleeffect ~= "" then PrecacheParticleSystem(kv.particleeffect) end
	self.trigger = WS.FindByName(kv.touch_trigger)
	self.inside = {}
end

function ENT:OnRemove()
	self.hazards:Unbind(self)
end

-- Who stands in the trigger now; nobody while it is disabled or gone.
function ENT:PlayersInTrigger()
	local now = {}
	if not (IsValid(self.trigger) and self.trigger:IsEnabled()) then return now end
	for _, ply in ipairs(WS.PlayersInside(self.trigger)) do now[ply] = true end
	return now
end

-- Ends of touch first, then new touches.
function ENT:PollTrigger()
	local now = self:PlayersInTrigger()
	for ply in pairs(self.inside) do
		if not now[ply] then
			self.inside[ply] = nil
			self.hazards:Left(self, ply)
		end
	end
	for ply in pairs(now) do
		if not self.inside[ply] then
			self.inside[ply] = true
			self.hazards:Touched(self, ply)
		end
	end
end

function ENT:Think()
	self:PollTrigger()
	self.hazards:Think(self)
	self:NextThink(CurTime())
	return true
end

function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	if not self.hazard:Accepts(input) then return false end
	self.hazards:Input(self, input, value)
	return true
end
