-- tf_point_weapon_mimic (CTFPointWeaponMimic): a binding to a
-- foundation.combat.weapon_mimic model through the combat controller.
-- Keyvalues WeaponType, SpeedMin, SpeedMax, SpreadAngle, Damage,
-- SplashRadius, Crits, ModelScale, ModelOverride, FireSound and
-- ParticleEffect (the last two stored and, as in TF2, never played); inputs
-- FireOnce, FireMultiple and DetonateStickies. It is on BLU. Arrows and
-- stickies are not fired: the first try logs once per map, and
-- DetonateStickies has nothing to set off.
ENT.Type = "point"
ENT.Base = "base_point"

local MODEL = "foundation.combat.weapon_mimic"
local UNSUPPORTED_MESSAGE = "tf_point_weapon_mimic: WeaponType %d (arrows, stickies) is not supported; not fired"
local loggedUnsupported = false

-- Keyvalues read as atof and atoi do: a non-number is 0. Missing ones take
-- the FGD's defaults.
local ATOF_FALLBACK = 0
local DEFAULTS = {
	weapontype = "0",
	speedmin = "1000",
	speedmax = "1000",
	damage = "75",
	splashradius = "50",
	spreadangle = "0",
	crits = "0",
	modelscale = "1",
}

local function Float(value)
	return tonumber(value) or ATOF_FALLBACK
end

local function Int(value)
	return math.floor(Float(value))
end

function ENT:KeyValue(key, value)
	self.kv = self.kv or {}
	self.kv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Initialize()
	local kv = setmetatable(self.kv or {}, { __index = DEFAULTS })
	local model = kv.modeloverride
	if model == "" then model = nil end
	if model then util.PrecacheModel(model) end
	self.weaponType = Int(kv.weapontype)
	self.combat = WS.Feature("combat")
	self.mimic = self.combat:BindWeaponMimic(self, {
		weaponType = self.weaponType,
		speedMin = Float(kv.speedmin),
		speedMax = Float(kv.speedmax),
		spreadAngle = Float(kv.spreadangle),
		damage = Float(kv.damage),
		splashRadius = Float(kv.splashradius),
		crits = Int(kv.crits) ~= 0,
		modelScale = Float(kv.modelscale),
		modelOverride = model,
	})
end

-- The team the combat controller sees.
function ENT:GetTeamNumber()
	return WS.require(MODEL).TEAM
end

function ENT:FireShots(count)
	if not self.mimic:Fires() then
		if loggedUnsupported then return end
		loggedUnsupported = true
		print(string.format(UNSUPPORTED_MESSAGE, self.weaponType))
		return
	end
	self.combat:FireWeaponMimic(self, self.mimic, count)
end

local ONE_SHOT = 1

local INPUTS = {
	fireonce = function(self) self:FireShots(ONE_SHOT) end,
	firemultiple = function(self, value)
		self:FireShots(WS.require(MODEL).FireCount(Int(value)))
	end,
	detonatestickies = function() end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
