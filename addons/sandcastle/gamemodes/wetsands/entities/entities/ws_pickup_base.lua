-- Common base for item_healthkit_* and item_ammopack_* (CTFPowerup, CItem).
-- A live player or AI war soldier of its team (TeamNum 0: anyone) who can
-- use it takes it:
-- a health kit heals ceil(max * size) and puts out fire, an ammo pack refills
-- each weapon by that share; the player alone hears the pickup sound, and
-- OnPlayerTouch fires. It comes back 10 seconds later with Item.Materialize,
-- or, with AutoMaterialize off, only when enabled again. Disabled pickups
-- are hidden and cannot be taken.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.Model = "models/items/medkit_small.mdl"
ENT.Size = "small"
ENT.Kind = "health"

-- The idle sequence plays, as TF2's powerups' does.
ENT.AutomaticFrameAdvance = true

if CLIENT then return end

local P = WS.PlayerRules

-- A kit's touch box.
local KIT_MINS = Vector(-16, -16, 0)
local KIT_MAXS = Vector(16, 16, 24)

local SOUNDS = {
	health = "HealthKit.Touch",
	ammo = "AmmoPack.Touch",
}

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "teamnum" then
		self.team = tonumber(value) or WS.TEAM_UNASSIGNED
	elseif k == "startdisabled" then
		self.startDisabled = value == "1"
	elseif k == "automaterialize" then
		self.autoMaterialize = value ~= "0"
	elseif k == "powerup_model" then
		self.powerupModel = value
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:TouchBounds()
	return KIT_MINS, KIT_MAXS
end

-- CTFPowerup::GetPowerupModel: the map's model when it exists.
function ENT:PowerupModel()
	if self.powerupModel and self.powerupModel ~= "" and util.IsValidModel(self.powerupModel) then
		return self.powerupModel
	end
	return self.Model
end

function ENT:Initialize()
	self:SetModel(self:PowerupModel())
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionBounds(self:TouchBounds())
	self:SetTrigger(true)
	self:AddSolidFlags(FSOLID_NOT_SOLID)
	self:ResetSequence(self:LookupSequence("idle"))
	self.team = self.team or WS.TEAM_UNASSIGNED
	if self.autoMaterialize == nil then self.autoMaterialize = true end
	self.respawning = false
	self:SetDisabled(self.startDisabled == true)
end

-- The server's cycle advances every frame, so the idle sequence plays.
function ENT:Think()
	self:NextThink(CurTime())
	return true
end

-- CTFPowerup::SetDisabled
function ENT:SetDisabled(disabled)
	self.disabled = disabled
	if disabled then
		self:SetNoDraw(true)
	elseif not self.respawning then
		self:SetNoDraw(false)
	elseif not self.autoMaterialize then
		self:Materialize()
	end
end

-- CTFPowerup::Materialize_Internal
function ENT:Materialize()
	if not self.disabled and self:GetNoDraw() then
		self:EmitSound("Item.Materialize")
		self:SetNoDraw(false)
	end
	self.respawning = false
end

-- CItem::Respawn, then CTFPowerup::Materialize once the respawn time is up.
function ENT:Respawn()
	self.respawning = true
	self:SetNoDraw(true)
	timer.Simple(P.ITEM_RESPAWN_TIME, function()
		if IsValid(self) and self.respawning and self.autoMaterialize then self:Materialize() end
	end)
end

-- A live player in the game, or a living team member (an AI war soldier).
local function Taker(ent)
	if not IsValid(ent) then return false end
	if ent:IsPlayer() then return WS.IsAliveInGame(ent) end
	return WS.TeamNumber(ent) ~= WS.TEAM_UNASSIGNED and ent:Health() > 0
end

-- CTFPowerup::ValidTouch
function ENT:ValidTouch(ent)
	if self.disabled or self.respawning or not Taker(ent) then return false end
	return self.team == WS.TEAM_UNASSIGNED or WS.TeamNumber(ent) == self.team
end

-- CHealthKit::MyTouch / CAmmoPack::MyTouch: whether the pickup was used. A
-- soldier carries no ammo to refill.
function ENT:MyTouch(ent)
	local ratio = P.PACK_RATIO[self.Size]
	if self.Kind == "ammo" then return ent:IsPlayer() and WS.GiveAmmoFraction(ent, ratio) end
	local given = P.HealthKitHeal(ent:Health(), ent:GetMaxHealth(), ratio)
	local burning = WS.InCondition(ent, P.COND.BURNING)
	if not P.HealthKitTaken(given, burning) then return false end
	ent:SetHealth(ent:Health() + given)
	WS.RemoveCondition(ent, P.COND.BURNING)
	return true
end

-- CItem::ItemTouch: a player alone hears it; a soldier's taking is heard
-- round it.
function ENT:Touch(ent)
	if not self:ValidTouch(ent) or not self:MyTouch(ent) then return end
	if ent:IsPlayer() then WS.PlaySoundTo(ent, self, SOUNDS[self.Kind]) else self:EmitSound(SOUNDS[self.Kind]) end
	self:TriggerOutput("OnPlayerTouch", ent)
	self:Respawn()
end

local INPUTS = {
	enable = function(self) self:SetDisabled(false) end,
	disable = function(self) self:SetDisabled(true) end,
	toggle = function(self) self:SetDisabled(not self.disabled) end,
	setteam = function(self, value) self.team = tonumber(value) or WS.TEAM_UNASSIGNED end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end