-- func_capturezone (CCaptureZone, func_capture_zone.cpp): where a flag's
-- carrier captures it, CTF's intelligence or MvM's bomb. Outputs: OnCapture,
-- OnCapTeam1, OnCapTeam2.
ENT.Type = "brush"
ENT.Base = "base_brush"

function ENT:KeyValue (key, value)
	local k = string.lower (key)
	self.wsKv = self.wsKv or {}
	self.wsKv [k] = value
	if k == "model" then self.brushModel = value end
	if string.sub (key, 1, 2) == "On" then self:StoreOutput (key, value) end
end

function ENT:Initialize ()
	if self.brushModel then self:SetModel (self.brushModel) end
	self:SetSolid (SOLID_NONE)
	self:SetNoDraw (true)
	local kv = self.wsKv or {}
	self.team = tonumber (kv.teamnum) or TF_TEAM_UNASSIGNED
	self.enabled = kv.startdisabled ~= "1"
	self:Publish ()
end

-- CCaptureZone::Touch: a zone caps for carriers of its team, or of any team
-- when it has none.
function ENT:MayCapture (carrierTeam)
	return self.team == TF_TEAM_UNASSIGNED or self.team == carrierTeam
end

-- Where each team's carrier takes the flag: the first enabled zone of its team.
function ENT:Publish ()
	for _, t in ipairs ({ TEAM_RED, TEAM_BLUE }) do
		local at = vector_origin
		for _, zone in ipairs (ents.FindByClass ("func_capturezone")) do
			if zone.enabled and zone:MayCapture (t) then
				at = zone:WorldSpaceCenter ()
				break
			end
		end
		SetGlobal2Vector ("ws_flag_zone_" .. t, at)
	end
end

function ENT:SetEnabled (enabled)
	self.enabled = enabled
	self:Publish ()
end

-- TF2's outputs number the game teams from 1: RED's OnCapTeam1, BLU's OnCapTeam2.
local TEAM_OUTPUT =
{
	[TEAM_RED] = "Team1",
	[TEAM_BLUE] = "Team2"
}

local function Contains (list, ent)
	for _, e in ipairs (list) do
		if e == ent then return true end
	end
	return false
end

local HULL = Vector (16, 16, 36)

-- Whether carrier stands in it: the gamemode's answer, or where the carrier is.
local function HasCarrier (self, carrier)
	local inside = hook.Run ("FlagMembersInside", self)
	if inside then return Contains (inside, carrier) end
	return self:WorldToLocal (carrier:WorldSpaceCenter ()):WithinAABox (self:OBBMins () - HULL, self:OBBMaxs () + HULL)
end

-- CCaptureZone::Touch: captures the flag of a carrier inside it, if the zone
-- may. Whether it did.
function ENT:TakeFlag (flag, carrier)
	if not self.enabled or not self:MayCapture (flag.flagModel:CarrierTeam ()) then return false end
	if not HasCarrier (self, carrier) then return false end
	local team = flag:Capture (carrier)
	if not team then return false end
	self:TriggerOutput ("OnCapture", carrier)
	if TEAM_OUTPUT [team] then self:TriggerOutput ("OnCap" .. TEAM_OUTPUT [team], carrier) end
	return true
end

local INPUTS =
{
	enable = function (self) self:SetEnabled (true) end,
	disable = function (self) self:SetEnabled (false) end,
	setteam = function (self, value)
		self.team = tonumber (value) or TF_TEAM_UNASSIGNED
		self:Publish ()
	end
}

-- Enable, Disable, SetTeam.
function ENT:AcceptInput (name, activator, caller, value)
	local handler = INPUTS [string.lower (name)]
	if not handler then return false end
	handler (self, value)
	return true
end
