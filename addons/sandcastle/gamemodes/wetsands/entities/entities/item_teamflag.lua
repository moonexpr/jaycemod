-- item_teamflag (CCaptureFlag, entity_capture_flag.cpp): CTF's intelligence
-- and MvM's bomb. A binding to the flag controller, which owns its model
-- (features.flag.model): who may pick it up, its carry, drop and return,
-- and its capture in a func_capturezone. Outputs: OnPickup,
-- OnPickupTeam1/2, OnDrop, OnReturn, OnCapture, OnCapTeam1/2.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

local MODEL_DEFAULT = "models/flag/briefcase.mdl"
-- The briefcase's skins: RED's, BLU's, then the neutral one.
local SKINS = {
	[WS.TEAM_RED] = 0,
	[WS.TEAM_BLUE] = 1,
}
local SKIN_NEUTRAL = 2

-- The client draws the model; the flag panel is the flag feature's view.
if CLIENT then return end

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	self.wsKv = self.wsKv or {}
	self.wsKv[k] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:WsSkin(team)
	return SKINS[team] or SKIN_NEUTRAL
end

function ENT:Initialize()
	local kv = self.wsKv or {}
	local model = kv.flag_model ~= "" and kv.flag_model or MODEL_DEFAULT
	util.PrecacheModel(model)
	self:SetModel(model)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_NONE)
	self:DrawShadow(false)
	local team = tonumber(kv.teamnum) or WS.TEAM_UNASSIGNED
	self:SetSkin(self:WsSkin(team))
	self.flag = WS.Feature("flag")
	self.flag:BindFlag(self, {
		team = team,
		returnTime = tonumber(kv.returntime),
		disabled = kv.startdisabled == "1",
	})
end

function ENT:OnRemove()
	self.flag:UnbindFlag(self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

-- Enable, Disable, ForceDrop, ForceReset, ForceResetSilent,
-- ForceResetAndDisableSilent, SetTeam, SetReturnTime.
function ENT:AcceptInput(name, activator, caller, value)
	return self.flag:FlagInput(self, string.lower(name), value, activator)
end
