-- tf_halloween_gift_spawn_location (CHalloweenGiftSpawnLocation): a place a
-- Halloween gift may appear. Once every map entity has spawned
-- (CTFGameRules::LevelInitPostEntity), and only while Halloween is on, it
-- hands its origin to the holiday controller and removes itself.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Initialize()
	local holiday = WETSAND.Feature("holiday")
	local Gift = WETSAND.require("foundation.holiday.gift")
	-- The next tick: tf_logic_holiday may spawn after this entity.
	timer.Simple(0, function()
		if not IsValid(self) or not holiday:HolidayActive(Gift.HOLIDAY) then return end
		holiday:AddGiftLocation(self:GetPos())
		self:Remove()
	end)
end
