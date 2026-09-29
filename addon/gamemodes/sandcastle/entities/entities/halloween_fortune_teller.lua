-- halloween_fortune_teller (CTFHalloweenFortuneTeller): Merasmus's booth, a
-- binding to a foundation.holiday.fortune model through the holiday
-- controller. Keyvalues red_teleport and blue_teleport; inputs
-- EnableFortuneTelling, DisableFortuneTelling, StartFortuneTelling and
-- EndFortuneTelling (Kill and AddOutput are the engine's); outputs
-- OnFortuneWarning, OnFortuneTold, OnFortuneCurse and OnFortuneEnd.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

if CLIENT then return end

local MODEL = "foundation.holiday.fortune"

function ENT:KeyValue(key, value)
	self.kv = self.kv or {}
	self.kv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	local kv = self.kv or {}
	local Fortune = WETSAND.require(MODEL)
	self:SetModel(Fortune.MODEL)
	self:ResetSequence(self:LookupSequence(Fortune.IDLE_SEQUENCE))
	self.holiday = WETSAND.Feature("holiday")
	self.fortune = self.holiday:BindFortuneTeller(self, {
		redTeleport = kv.red_teleport,
		blueTeleport = kv.blue_teleport,
	})
end

function ENT:OnRemove()
	self.holiday:UnbindFortuneTeller(self)
end

function ENT:Think()
	self.holiday:ThinkFortune(self)
	self:NextThink(CurTime())
	return true
end

function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	if not self.fortune:Accepts(input) then return false end
	self.holiday:FortuneInput(self, input)
	return true
end
