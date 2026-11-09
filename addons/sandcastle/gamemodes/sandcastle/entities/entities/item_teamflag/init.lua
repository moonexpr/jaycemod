-- item_teamflag (CCaptureFlag, entity_capture_flag.cpp): CTF's intelligence
-- and MvM's bomb. It holds its state (state.lua), thinks for itself, takes
-- its inputs, fires its outputs, networks its state and puts itself where its
-- state says, in sandbox and gameplay alike. func_capturezone and
-- func_respawnflag act on it as its carrier meets them. It assumes nothing of
-- the scenario: what one says is optional (Rules), and a capture is reported
-- to round_manager. A gamemode may answer its hooks (FlagTeam,
-- FlagCarrierAlive, FlagMembersInside, FlagEvent); unanswered, it goes by
-- players. Outputs: OnPickup,
-- OnPickupTeam1/2, OnDrop, OnReturn, OnCapture, OnCapTeam1/2.
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local MODEL_DEFAULT = "models/flag/briefcase.mdl"
-- The briefcase's skins: RED's, BLU's, then the neutral one.
local SKINS = {
	[TEAM_RED] = 0,
	[TEAM_BLUE] = 1,
}
local SKIN_NEUTRAL = 2

local THINK_INTERVAL = 0.1
local State = include("state.lua")
local PICKUP, DROP, CAPTURE, RETURN, CARRIED = State.PICKUP, State.DROP, State.CAPTURE, State.RETURN, State.CARRIED

-- What the scenario says of flags, each with the flag's own answer if it says
-- nothing: anyone but a flag's owners may take it, whenever, and a capture counts.
local function Rules()
	local rules = game_manager.GetCurrentScenario():GetRules()
	return {
		ownersCarry = rules.FlagOwnersCarry or false,
		mayBeCapped = rules.FlagMayBeCapped ~= false,
		invaders = rules.FlagInvaders,
		scores = rules.FlagScores ~= false,
	}
end

local function TeamOf(ent)
	local team = hook.Run("FlagTeam", ent)
	if team ~= nil then return team end
	return ent:Team()
end

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
	self.team = tonumber(kv.teamnum) or TF_TEAM_UNASSIGNED
	self.returnTime = tonumber(kv.returntime)
	self.startDisabled = kv.startdisabled == "1"
	self:SetSkin(self:WsSkin(self.team))
	self.wsHome, self.wsHomeAngles = self:GetPos(), self:GetAngles()
	self.flagModel = State.New({ team = self.team, returnTime = self.returnTime, disabled = self.startDisabled })
	self:Publish()
	GAMEMODE:AddController({ type = "flag", ent = self })
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

-- Outputs ------------------------------------------------------------------------------

-- TF2's outputs number the game teams from 1: RED's OnCapTeam1, BLU's OnCapTeam2.
local TEAM_OUTPUT = {
	[TEAM_RED] = "Team1",
	[TEAM_BLUE] = "Team2",
}
local FLAG_OUTPUTS = {
	[PICKUP] = "OnPickup",
	[DROP] = "OnDrop",
	[CAPTURE] = "OnCapture",
	[RETURN] = "OnReturn",
}
-- The team outputs a flag fires beside its own (OnPickupTeam1, OnCapTeam2...).
local FLAG_TEAM_OUTPUTS = {
	[PICKUP] = "OnPickup",
	[CAPTURE] = "OnCap",
}

-- e = { kind, team }, one of the game's events.
function ENT:FireOutputs(e, activator)
	self:TriggerOutput(FLAG_OUTPUTS[e.kind], activator)
	local teamOutput = FLAG_TEAM_OUTPUTS[e.kind]
	if teamOutput and TEAM_OUTPUT[e.team] then self:TriggerOutput(teamOutput .. TEAM_OUTPUT[e.team], activator) end
end

-- Publishing ---------------------------------------------------------------------------

function ENT:Publish()
	local flag = self.flagModel
	self:SetNW2Int("ws_flag_team", flag:Team())
	self:SetNW2String("ws_flag_state", flag:State())
	self:SetNW2Bool("ws_flag_enabled", flag:Enabled())
	self:SetNW2Entity("ws_flag_carrier", flag:Carrier() or NULL)
	self:SetNW2Int("ws_flag_carrier_team", flag:CarrierTeam())
end

-- What the games being played count of the flags, if any does.
function ENT:PublishTally()
	local objective = {}
	game_manager.RunActive("Standing", objective)
	if not objective.captures then return end
	SetGlobal2Int("ws_flag_caps_" .. TEAM_RED, objective.captures[TEAM_RED])
	SetGlobal2Int("ws_flag_caps_" .. TEAM_BLUE, objective.captures[TEAM_BLUE])
	SetGlobal2Int("ws_flag_caplimit", objective.caplimit)
	SetGlobal2Bool("ws_flag_scores", Rules().scores)
end

-- Where it sits ------------------------------------------------------------------------

-- Where a carried flag rides: behind the carrier's shoulders.
local CARRY_OFFSET = Vector(-16, 0, 48)
local DROP_TRACE = Vector(0, 0, -1024)
local DROP_LIFT = Vector(0, 0, 16)
-- TF2 straps the case to its players' "flag" attachment; HL2's skeletons
-- have none, so it rides their upper spine (CARRY_BONE), upright on the
-- carrier's back BACK_DEPTH behind the bone, its flat face outward, and
-- moves with the body (CarryBone). A carrier without that bone carries it
-- at CARRY_OFFSET from its origin.
local CARRY_BONE, BACK_DEPTH = "ValveBiped.Bip01_Spine2", 10
-- The carry bone of each model, looked up once (false: the model has none).
local carryBones = {}

local function CarryBone(carrier)
	local model = carrier:GetModel()
	if carryBones[model] == nil then carryBones[model] = carrier:LookupBone(CARRY_BONE) or false end
	return carryBones[model] or nil
end

hook.Add("PlayerSpawn", "item_teamflag", function(ply)
	timer.Simple(0, function() if IsValid(ply) then CarryBone(ply) end end) -- once its model is set
end)

function ENT:Carry(carrier)
	local bone = CarryBone(carrier)
	if not bone then
		self:SetParent(carrier)
		self:SetLocalPos(CARRY_OFFSET)
		self:SetLocalAngles(angle_zero)
		return
	end
	-- the server sets the bones up as it is asked for one (SetupBones is the client's)
	local bonePos, boneAng = carrier:GetBonePosition(bone)
	local forward = carrier:GetForward()
	-- the case's long side up, its thin side facing back
	local pos, ang = bonePos - forward * BACK_DEPTH, carrier:GetUp():AngleEx(-forward)
	self:FollowBone(carrier, bone)
	local localPos, localAng = WorldToLocal(pos, ang, bonePos, boneAng)
	self:SetLocalPos(localPos)
	self:SetLocalAngles(localAng)
end

-- On the ground under where the carrier stood.
function ENT:PutDown(at)
	self:SetParent(NULL)
	local tr = util.TraceLine({
		start = at + DROP_LIFT,
		endpos = at + DROP_TRACE,
		mask = MASK_SOLID_BRUSHONLY,
	})
	self:SetPos(tr.Hit and tr.HitPos or at)
	self:SetAngles(Angle(0, self:GetAngles().y, 0))
end

function ENT:GoHome()
	self:SetParent(NULL)
	self:SetPos(self.wsHome)
	self:SetAngles(self.wsHomeAngles)
end

-- What its events do -------------------------------------------------------------------

function ENT:Apply(events, activator)
	local flag = self.flagModel
	local scores = Rules().scores
	-- a new carrier, or none: its path through the reset zones starts afresh
	self.carriedAt = nil
	for _, e in ipairs(events) do
		if e.kind == PICKUP then
			self:Carry(flag:Carrier())
		elseif e.kind == DROP then
			self:PutDown(activator:GetPos())
		else
			self:GoHome()
		end
		self:FireOutputs(e, activator)
		hook.Run("FlagEvent", self, e, activator)
		if e.kind == CAPTURE and scores then
			-- counted by the game being played; rounds won are the team's score
			round_manager.AddTeamScore({ team = e.team, score = 0, activator = activator, event = "flag_capture" })
		end
	end
	self:Publish()
end

-- PointInRespawnFlagZone, swept: whether a move from `from` to `to` ends in
-- or passes through an enabled func_respawnflag (the flag thinks every
-- THINK_INTERVAL; a carrier falls further than a zone is deep in one).
local function InResetZone(from, to)
	for _, zone in ipairs(ents.FindByClass("func_respawnflag")) do
		if zone.enabled and zone:Crossed(from, to) then return true end
	end
	return false
end

-- Dropped where its carrier stands (CCaptureFlag::Drop), reset when the
-- carrier passed through a func_respawnflag since the last think.
function ENT:Drop(now)
	local carrier = self.flagModel:Carrier()
	local at = IsValid(carrier) and carrier or self
	local pos = at:GetPos()
	self:Apply(self.flagModel:Drop(now, InResetZone(self.carriedAt or pos, pos)), at)
end

-- Home at once, announced. A carried flag is dropped first, by its carrier.
function ENT:Reset()
	local flag = self.flagModel
	if flag:State() ~= CARRIED then
		self:Apply(flag:Reset(false), self)
		return
	end
	local carrier = flag:Carrier()
	self:Apply(flag:Drop(CurTime(), true), IsValid(carrier) and carrier or self)
end

-- Captured by carrier, in a zone that takes it. The capturing team, or nil if it is not carried.
function ENT:Capture(carrier)
	local events = self.flagModel:Capture()
	if #events == 0 then return nil end
	self:Apply(events, carrier)
	return events[1].team
end

-- CCaptureFlag::PickUp from outside the touch: carrier takes the flag if the
-- rules let it. Returns whether it did.
function ENT:Give(carrier)
	local events = self.flagModel:PickUp(carrier, TeamOf(carrier), Rules())
	if #events == 0 then return false end
	self:Apply(events, carrier)
	return true
end

function ENT:ForgetCarry()
	self.carriedAt = nil
end

local function DropCarriedBy(ent)
	for _, controller in ipairs(GAMEMODE:GetControllers("flag")) do
		local flag = controller.ent
		if flag.flagModel:Carrier() == ent then flag:Drop(CurTime()) end
	end
end

-- The carrier drops the flag where it died; in a func_respawnflag it goes home.
hook.Add("PlayerDeath", "item_teamflag", DropCarriedBy)

-- A carrier removed (a disconnect, a soldier's corpse cleaned up) drops the
-- flag before it would go with them.
hook.Add("EntityRemoved", "item_teamflag", function(ent)
	if GAMEMODE then DropCarriedBy(ent) end
end)

-- Inputs -------------------------------------------------------------------------------

local INPUTS = {
	enable = function(flag) return flag:SetEnabled(true) end,
	disable = function(flag) return flag:SetEnabled(false) end,
	forcedrop = function(flag, _, inResetZone) return flag:Drop(CurTime(), inResetZone) end,
	forcereset = function(flag) return flag:Reset(false) end,
	forceresetsilent = function(flag) return flag:Reset(true) end,
	forceresetanddisablesilent = function(flag) return flag:SetEnabled(false) end,
	setteam = function(flag, value)
		flag:SetTeam(tonumber(value) or TF_TEAM_UNASSIGNED)
		return {}
	end,
	setreturntime = function(flag, value)
		flag:SetReturnTime(tonumber(value))
		return {}
	end,
}

-- Enable, Disable, ForceDrop, ForceReset, ForceResetSilent,
-- ForceResetAndDisableSilent, SetTeam, SetReturnTime.
function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	local handler = INPUTS[input]
	if not handler then return false end
	local flag = self.flagModel
	local carrier = flag:Carrier()
	local events = handler(flag, value, IsValid(carrier) and InResetZone(carrier:GetPos(), carrier:GetPos()))
	self:Apply(events, IsValid(carrier) and carrier or activator)
	if input == "setteam" then self:SetSkin(self:WsSkin(flag:Team())) end
	return true
end

-- Thinking -----------------------------------------------------------------------------

local function Alive(ent)
	if not IsValid(ent) then return false end
	local alive = hook.Run("FlagCarrierAlive", ent)
	if alive ~= nil then return alive end
	return ent:IsPlayer() and ent:Alive()
end

local HULL = Vector(16, 16, 36)

-- Who stands on it: the gamemode's answer, or the living players at it.
local function StandingOn(ent)
	local answer = hook.Run("FlagMembersInside", ent)
	if answer then return answer end
	local inside = {}
	local mins, maxs = ent:OBBMins() - HULL, ent:OBBMaxs() + HULL
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and ent:WorldToLocal(ply:WorldSpaceCenter()):WithinAABox(mins, maxs) then
			inside[#inside + 1] = ply
		end
	end
	return inside
end

-- Whether carrier stands in an active respawn room the flag drops in.
local function InOwnRespawnRoom(carrier, t, invaders)
	local point = carrier:WorldSpaceCenter()
	for _, room in ipairs(ents.FindByClass("func_respawnroom")) do
		if room.active and State.DropsIn(room.team, t, invaders) and room:PointIsWithin(point) then return true end
	end
	return false
end

local function ThinkCarried(self, now, q)
	local flag = self.flagModel
	local carrier = flag:Carrier()
	local t = flag:CarrierTeam()
	if not Alive(carrier) or TeamOf(carrier) ~= t or InOwnRespawnRoom(carrier, t, q.invaders) then
		self:Drop(now)
		return
	end
	local pos = carrier:GetPos()
	local from = self.carriedAt or pos
	for _, zone in ipairs(ents.FindByClass("func_respawnflag")) do
		if zone:CarrierCrossed(self, from, pos) then return end
	end
	self.carriedAt = pos
	for _, zone in ipairs(ents.FindByClass("func_capturezone")) do
		if zone:TakeFlag(self, carrier) then return end
	end
end

local function ThinkLoose(self, now, q)
	local flag = self.flagModel
	self:Apply(flag:Think(now), self)
	for _, candidate in ipairs(StandingOn(self)) do
		local events = flag:PickUp(candidate, TeamOf(candidate), q)
		if #events > 0 then
			self:Apply(events, candidate)
			return
		end
	end
end

function ENT:Think()
	self:NextThink(CurTime() + THINK_INTERVAL)
	local think = self.flagModel:State() == CARRIED and ThinkCarried or ThinkLoose
	think(self, CurTime(), Rules())
	self:PublishTally()
	return true
end
