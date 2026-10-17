-- filter_tf_damaged_by_weapon_in_slot (FilterDamagedByWeaponInSlot): a
-- damage filter, bound to foundation.combat.weapon_slot_filter. Keyvalues
-- weaponSlot and Negated. Engine entities consult it through
-- PassesDamageFilter (pl_corruption's filter_multi, set on players by
-- SetDamageFilter) and PassesFilter. A slot other than melee logs once per
-- map and passes no damage.
ENT.Type = "filter"
ENT.Base = "base_filter"

local MODEL = "foundation.combat.weapon_slot_filter"
local UNSUPPORTED_MESSAGE = "filter_tf_damaged_by_weapon_in_slot: weaponSlot %d is not supported (only melee, 2); it passes no damage"
local loggedUnsupported = false

-- FIELD_INTEGER keyvalues read as atoi does: a non-number is 0.
local ATOI_FALLBACK = 0

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "weaponslot" then
		self.slot = math.floor(tonumber(value) or ATOI_FALLBACK)
	elseif k == "negated" then
		-- Hammer may store the choice's label; only "1" negates.
		self.negated = value == "1"
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.rules = WS.require(MODEL)
	self.slot = self.slot or ATOI_FALLBACK
	self.negated = self.negated or false
	if not self.rules.Supported(self.slot) and not loggedUnsupported then
		loggedUnsupported = true
		print(string.format(UNSUPPORTED_MESSAGE, self.slot))
	end
end

function ENT:PassesFilter(trigger, ent)
	return self.rules.PassesEntity(self.negated)
end

function ENT:PassesDamageFilter(dmg)
	local attacker = dmg:GetAttacker()
	return self.rules.PassesDamage(self.slot, self.negated, {
		byPlayer = IsValid(attacker) and attacker:IsPlayer(),
		dmgType = dmg:GetDamageType(),
	})
end
