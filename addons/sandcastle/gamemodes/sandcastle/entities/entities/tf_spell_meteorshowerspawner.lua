-- tf_spell_meteorshowerspawner (CTFSpell_MeteorShowerSpawner): where a
-- meteor shower landed. Not a projectile: it stays put while the spells
-- controller ticks its Shot, which drops the meteors and says when it is
-- done (features.spells.meteor). The caster port spawns it with
-- SetOwner(caster) and Configure{ spell, normal, team } before Spawn.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:Configure(config)
	self.configured = config
end

function ENT:Initialize()
	self.spells = WS.Feature("spells")
	self.spells:BindSpellProjectile(self, self.configured.spell, self.configured)
end

function ENT:OnRemove()
	self.spells:Unbind(self)
end

function ENT:GetTeamNumber()
	return self.configured.team
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Think()
	if self.spells:ThinkShot(self) then
		self:Remove()
		return
	end
	self:NextThink(CurTime())
	return true
end
