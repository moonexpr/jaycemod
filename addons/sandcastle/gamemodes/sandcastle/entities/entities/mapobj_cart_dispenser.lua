-- mapobj_cart_dispenser (CObjectCartDispenser, tf_obj_dispenser.cpp): the
-- payload cart's dispenser. It heals teammates standing in its touch
-- trigger at the level's rate and resupplies their ammo once a second. It
-- has no model and cannot be damaged; its metal never runs out.
ENT.Type = "point"
ENT.Base = "base_point"

local FIRST_LEVEL, MAX_LEVEL = 1, 3         -- the dispenser's upgrade levels, indexing the rates
local HEAL_RATES = { 10.0, 15.0, 20.0 } -- g_flDispenserHealRates, health per second
local AMMO_RATES = { 0.2, 0.3, 0.4 }    -- g_flDispenserAmmoRates, of each reserve per dose
local AMMO_INTERVAL = 1.0               -- after someone took ammo
local AMMO_RETRY = 0.1                  -- when nobody did, so a newcomer gets it at once
local DEFAULT_RADIUS = 64               -- GetDispenserRadius, for a dispenser without touch_trigger
local SF_IGNORE_LOS = 4                 -- SF_DISPENSER_IGNORE_LOS
local THINK_TIME = 0.1
local HULL = Vector(16, 16, 36)

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	self.wsKv = self.wsKv or {}
	self.wsKv[k] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Key(name, default)
	local v = (self.wsKv or {})[name]
	if v == nil or v == "" then return default end
	return v
end

function ENT:Initialize()
	self.team = tonumber(self:Key("teamnum", WS.TEAM_RED)) or WS.TEAM_RED
	self.spawnflags = tonumber(self:Key("spawnflags", 0)) or 0
	self.level = FIRST_LEVEL
	self.disabled = false
	self.healCarry = setmetatable({}, { __mode = "k" })
	-- OnGoActive: the first dose half a second after it goes active
	self.nextAmmo = CurTime() + 0.5
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

-- Players in range: the touch_trigger's volume, or a cube of DEFAULT_RADIUS.
function ENT:Touching()
	local trigger = WS.FindByName(self:Key("touch_trigger"))
	if IsValid(trigger) then
		if not trigger:IsEnabled() then return {} end
		return WS.PlayersInside(trigger)
	end
	local inside, extent = {}, Vector(DEFAULT_RADIUS, DEFAULT_RADIUS, DEFAULT_RADIUS) + HULL
	for _, ply in ipairs(player.GetAll()) do
		if WS.IsAliveInGame(ply) and (ply:WorldSpaceCenter() - self:GetPos()):WithinAABox(-extent, extent) then
			inside[#inside + 1] = ply
		end
	end
	return inside
end

local MASK_DISPENSER = bit.bor(MASK_BLOCKLOS, CONTENTS_WINDOW)

-- CouldHealTarget: a teammate the dispenser can see (unless the map waives it).
function ENT:CouldHeal(ply)
	if WS.TeamOf(ply) ~= self.team then return false end
	if bit.band(self.spawnflags, SF_IGNORE_LOS) ~= 0 then return true end
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = self:GetPos(), mask = MASK_DISPENSER, filter = { ply, self:GetParent() } })
	return not tr.Hit
end

-- Heal whole points at the level's rate, carrying the fraction between thinks.
function ENT:Heal(ply, dt)
	local max = ply:GetMaxHealth()
	if ply:Health() >= max then
		self.healCarry[ply] = 0
		return
	end
	local carry = (self.healCarry[ply] or 0) + HEAL_RATES[self.level] * dt
	local whole = math.floor(carry)
	self.healCarry[ply] = carry - whole
	if whole > 0 then ply:SetHealth(math.min(max, ply:Health() + whole)) end
end

-- DispenseAmmo: a share of every reserve; the pickup sound when anything was taken.
function ENT:DispenseAmmo(ply)
	if not WS.GiveAmmoFraction(ply, AMMO_RATES[self.level]) then return false end
	EmitSound("BaseCombatCharacter.AmmoPickup", self:GetPos())
	return true
end

-- DispenseThink
function ENT:Think()
	self:NextThink(CurTime() + THINK_TIME)
	if self.disabled then return true end
	local dispenseAmmo = self.nextAmmo <= CurTime()
	local received = false
	for _, ply in ipairs(self:Touching()) do
		if self:CouldHeal(ply) then
			self:Heal(ply, THINK_TIME)
			if dispenseAmmo and self:DispenseAmmo(ply) then received = true end
		end
	end
	if dispenseAmmo then self.nextAmmo = CurTime() + (received and AMMO_INTERVAL or AMMO_RETRY) end
	return true
end

local function Ignore() end

local INPUTS = {
	enable = function(self) self.disabled = false end,
	disable = function(self) self.disabled = true end,
	-- CBaseObject Show/Hide re-enable and disable the object
	show = function(self) self.disabled = false end,
	hide = function(self) self.disabled = true end,
	setdispenserlevel = function(self, value)
		local level = tonumber(value)
		if level and level >= FIRST_LEVEL and level <= MAX_LEVEL then self.level = level end
	end,
	setteam = function(self, value) self.team = tonumber(value) or self.team end,
	-- Accepted with no effect: GMod has no TF2 conditions for the Halloween
	-- crit bonus, and a cart dispenser takes no damage and has no builder.
	firehalloweenbonus = Ignore,
	setbuilder = Ignore,
	sethealth = Ignore,
	addhealth = Ignore,
	removehealth = Ignore,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
