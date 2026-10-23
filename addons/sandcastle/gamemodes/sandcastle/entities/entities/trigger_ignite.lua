-- trigger_ignite (CTriggerIgnite, tf_triggers.cpp): sets players who walk
-- in alight and burns everyone inside by a share of their max health (the
-- lava on cp_lavapit_final, the fires on cp_gravelpit_snowy). A binding to
-- features.hazards.ignite, loaded by the first one on a map: this feeds
-- it the players who pass the filter as they come and go, and carries out
-- its events (the ignite particle and sound, BURNING, burn damage).
ENT.Type = "brush"
ENT.Base = "ws_trigger_volume"

local IGNITE_MODEL = "features.hazards.ignite"

-- The model's port on the players' conditions.
local PLAYERS = {
	InCond = function(_, ply, cond) return WS.InCondition(ply, cond) end,
	MaxHealth = function(_, ply) return ply:GetMaxHealth() end,
}

local function Effects(Ignite)
	return {
		[Ignite.IGNITE] = function(self, e)
			local pos = e.target:GetPos()
			if self.particle then ParticleEffect(self.particle, pos, angle_zero) end
			if self.sound then EmitSound(self.sound, pos, self:EntIndex()) end
			if e.duration then WS.AddCondition(e.target, WS.PlayerRules.COND.BURNING, e.duration) end
		end,
		[Ignite.DAMAGE] = function(self, e)
			local info = DamageInfo()
			info:SetDamage(e.amount)
			info:SetDamageType(DMG_BURN)
			info:SetAttacker(self)
			info:SetInflictor(self)
			e.target:TakeDamageInfo(info)
		end,
	}
end

local function Apply(self, events)
	for _, e in ipairs(events) do self.effects[e.kind](self, e) end
end

function ENT:TriggerInit()
	local Ignite = WS.require(IGNITE_MODEL)
	self.ignite = Ignite.New({
		burnDuration = tonumber(self:Key("burn_duration")),
		damagePercentPerSecond = tonumber(self:Key("damage_percent_per_second")),
	}, PLAYERS)
	self.effects = Effects(Ignite)
	self.particle = self:Key("ignite_particle_name")
	self.sound = self:Key("ignite_sound_name")
	if self.particle then PrecacheParticleSystem(self.particle) end
	self.inside = {} -- the players the model is burning
end

-- CTriggerIgnite::StartTouch: only those who pass the filter.
function ENT:PlayerStartTouch(ply)
	if not self:PassesTriggerFilters(ply) then return end
	self.inside[ply] = true
	Apply(self, self.ignite:StartTouch(CurTime(), ply))
end

function ENT:PlayerEndTouch(ply)
	if not self.inside[ply] then return end
	self.inside[ply] = nil
	self.ignite:EndTouch(ply)
end

-- BurnThink. A player who left the server leaves the fire too.
function ENT:TriggerThink()
	for ply in pairs(self.inside) do
		if not IsValid(ply) then self:PlayerEndTouch(ply) end
	end
	Apply(self, self.ignite:Think(CurTime()))
end
