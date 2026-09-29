-- tf_spell_pickup (CSpellPickup): a spellbook pickup on wetsand_pickup_base.
-- Keyvalue tier (0 common, 1 rare) picks the skin and, for a rare one, the
-- _major model. Any living caster of its team (TeamNum 0: any) that holds a
-- spellbook collects it through the spells controller, which rolls a spell
-- (a common pickup waits while the book holds or rolls one); a player
-- alone hears Halloween.spell_pickup or _rare, and OnPlayerTouch fires. A
-- map's pickup comes back 10 seconds later, as the base's do.
--
-- A skeleton king's drop (the holiday controller's DropSpellPickup) comes
-- with Configure{ tier, dropped = true, velocity } before Spawn: it is
-- thrown (CTFPowerup::DropSingleInstance), is taken once, and is gone after
-- TF_POWERUP_LIFETIME.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "wetsand_pickup_base"
ENT.Spawnable = false
ENT.Model = "models/props_halloween/hwn_spellbook_upright.mdl"

if CLIENT then return end

local Base = baseclass.Get("wetsand_pickup_base")

local MAJOR_MODEL = "models/props_halloween/hwn_spellbook_upright_major.mdl"
local SOUND = "Halloween.spell_pickup"
local RARE_SOUND = "Halloween.spell_pickup_rare"
local OUTPUT = "OnPlayerTouch"
local DROPPED_LIFETIME = 30 -- TF_POWERUP_LIFETIME

-- FIELD_INTEGER keyvalues read as atoi does: a non-number is 0.
local ATOI_FALLBACK = 0

function ENT:KeyValue(key, value)
	if string.lower(key) == "tier" then
		self.tier = math.floor(tonumber(value) or ATOI_FALLBACK)
		return
	end
	Base.KeyValue(self, key, value)
end

function ENT:Configure(config)
	self.tier = config.tier
	self.dropped = config.dropped
	self.launch = config.velocity
end

-- CSpellPickup::GetPowerupModel
function ENT:PowerupModel()
	if self.tier == self.set.TIER_RARE then return MAJOR_MODEL end
	return Base.PowerupModel(self)
end

-- m_nTier starts at 0.
function ENT:Initialize()
	self.set = WETSAND.require("foundation.spells.halloween")
	self.spells = WETSAND.Feature("spells")
	self.tier = self.tier or self.set.TIER_COMMON
	Base.Initialize(self)
	self:SetSkin(self.tier)
	if self.dropped then self:Throw() end
end

-- CTFPowerup::DropSingleInstance
function ENT:Throw()
	self:SetMoveType(MOVETYPE_FLYGRAVITY)
	self:SetMoveCollide(MOVECOLLIDE_FLY_BOUNCE)
	self:SetVelocity(self.launch)
	SafeRemoveEntityDelayed(self, DROPPED_LIFETIME)
end

-- CTFPowerup::ValidTouch, for any caster: the spells controller judges
-- whether it is alive and holds a book.
function ENT:OpenTo(other)
	if self.disabled or self.respawning then return false end
	return self.team == WETSAND.TEAM_UNASSIGNED or WETSAND.Feature("combat"):TeamOf(other) == self.team
end

-- CSpellPickup::MyTouch: a rare pickup's sound is _rare.
function ENT:PickupSound()
	if self.tier > self.set.TIER_COMMON then return RARE_SOUND end
	return SOUND
end

function ENT:Touch(other)
	if not self:OpenTo(other) then return end
	local taken = self.spells:Pickup(other, self.tier)
	if not taken then return end
	if other:IsPlayer() then WETSAND.PlaySoundTo(other, self, self:PickupSound()) end
	self:TriggerOutput(OUTPUT, other)
	if self.dropped then
		self:Remove()
	else
		self:Respawn()
	end
end
