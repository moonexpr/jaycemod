-- trigger_stun (CTriggerStun): trigger_delay after the first touch, stuns
-- every player inside every 0.5s while it finds anyone; a player who leaves
-- without having been stunned in the last pass is stunned on the way out.
-- The stun is WS.StunPlayer's: stun_type 0 slows by move_speed_reduction,
-- 1 also takes controls, 2 is the loser state (no attacking).
ENT.Type = "brush"
ENT.Base = "ws_trigger_volume"

local STUN_INTERVAL = 0.5

function ENT:TriggerInit()
	self.delay = tonumber(self:Key("trigger_delay", 0)) or 0
	self.duration = tonumber(self:Key("stun_duration", 0)) or 0
	self.reduction = tonumber(self:Key("move_speed_reduction", 0)) or 0
	local MOVEMENT = WS.PlayerRules.STUN_TYPE.MOVEMENT
	self.flags = WS.PlayerRules.StunFlags(tonumber(self:Key("stun_type", MOVEMENT)) or MOVEMENT)
	self.stunned = {}
end

-- CTriggerStun::StunEntity: only what can take damage, so not the dead.
function ENT:StunEntity(ply)
	if not ply:Alive() or not self:PassesTriggerFilters(ply) then return false end
	WS.StunPlayer(ply, self.duration, self.reduction, self.flags)
	self:TriggerOutput("OnStunPlayer", ply)
	self.stunned[ply] = true
	return true
end

-- CTriggerStun::Touch starts the stun think.
function ENT:PlayerTouch()
	self.nextStun = self.nextStun or CurTime() + self.delay
end

-- CTriggerStun::StunThink / StunAllTouchers
function ENT:TriggerThink()
	if not self.nextStun or CurTime() < self.nextStun then return end
	self.stunned = {}
	local count = 0
	for ply in pairs(self.touching) do
		if IsValid(ply) and self:StunEntity(ply) then count = count + 1 end
	end
	self.nextStun = count > 0 and CurTime() + STUN_INTERVAL or nil
end

-- CTriggerStun::EndTouch
function ENT:PlayerEndTouch(ply)
	if self:PassesTriggerFilters(ply) and not self.stunned[ply] then self:StunEntity(ply) end
end
