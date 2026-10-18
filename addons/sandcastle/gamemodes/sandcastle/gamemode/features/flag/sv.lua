-- The flag feature's controller. It owns a flag model (features.flag.model)
-- per item_teamflag and the map's func_capturezones. Every tick slice it
-- lets the players and team members (the AI war's soldiers) standing on a
-- free flag pick it up, drops a flag whose carrier died, left or changed
-- team, returns a dropped flag whose time is up, and captures a flag whose
-- carrier stands in a zone of its team. It carries the flag on the
-- carrier's back, fires the flag's and the zone's outputs, plays CTF's
-- announcer lines, and in CTF counts captures toward tf_flag_caplimit,
-- winning the round there (WINREASON_FLAG_CAPTURE_LIMIT). The mode decides
-- who carries (MvM's bomb is BLU's own) and whether captures score.
--
-- It publishes each flag's state on the flag (NW2 ws_flag_*) and the
-- tally, the limit and each team's zone (ws_flag_*) for the flag panel.
--
-- Loaded by item_teamflag and func_capturezone. It loads rounds.
local Flag = WS.require("features.flag.model")
local Rounds = WS.require("foundation.rounds")

local NOBODY, RED, BLUE = WS.TEAM_UNASSIGNED, WS.TEAM_RED, WS.TEAM_BLUE
local GAME_TEAMS = { RED, BLUE }
local THINK_INTERVAL = 0.1
local THINK_HOOK = "ws_flag"

local caplimit = CreateConVar("tf_flag_caplimit", tostring(Flag.CAPLIMIT_DEFAULT), { FCVAR_NOTIFY, FCVAR_REPLICATED },
	"Number of captures to win")

-- TF2's outputs number the game teams from 1: RED's OnCapTeam1, BLU's OnCapTeam2.
local TEAM_OUTPUT = {
	[RED] = "Team1",
	[BLUE] = "Team2",
}
local FLAG_OUTPUTS = {
	[Flag.PICKUP] = "OnPickup",
	[Flag.DROP] = "OnDrop",
	[Flag.CAPTURE] = "OnCapture",
	[Flag.RETURN] = "OnReturn",
}
-- The team outputs a flag fires beside its own (OnPickupTeam1, OnCapTeam2...).
local FLAG_TEAM_OUTPUTS = {
	[Flag.PICKUP] = "OnPickup",
	[Flag.CAPTURE] = "OnCap",
}

-- Where a carried flag rides: behind the carrier's shoulders.
local CARRY_OFFSET = Vector(-16, 0, 48)
local DROP_TRACE = Vector(0, 0, -1024)
local DROP_LIFT = Vector(0, 0, 16)

local Controller = {
	rounds = WS.Feature("rounds"),
	flags = {}, -- item_teamflag -> its model
	zones = {}, -- func_capturezone -> { team, enabled }
	tally = Flag.NewTally(),
	nextThink = 0,
}

-- CTFGameRules::Activate: an item_teamflag makes the game CTF.
Controller.rounds:SetMode(Flag.Mode)

local function Mode()
	return Controller.rounds:Mode()
end

-- Publishing ----------------------------------------------------------------------------

local function PublishFlag(ent, flag)
	ent:SetNW2Int("ws_flag_team", flag:Team())
	ent:SetNW2String("ws_flag_state", flag:State())
	ent:SetNW2Bool("ws_flag_enabled", flag:Enabled())
	ent:SetNW2Entity("ws_flag_carrier", flag:Carrier() or NULL)
	ent:SetNW2Int("ws_flag_carrier_team", flag:CarrierTeam())
end

local function PublishTally(self)
	for _, t in ipairs(GAME_TEAMS) do SetGlobal2Int("ws_flag_caps_" .. t, self.tally:Captures(t)) end
	SetGlobal2Int("ws_flag_caplimit", caplimit:GetInt())
	SetGlobal2Bool("ws_flag_scores", Mode().FLAG_CAPS_SCORE)
end

-- Where a team's carrier takes the flag: the first enabled zone of its team.
local function PublishZones(self)
	for _, t in ipairs(GAME_TEAMS) do
		local at = vector_origin
		for ent, zone in pairs(self.zones) do
			if zone.enabled and Flag.MayCapture(zone.team, t) then
				at = ent:WorldSpaceCenter()
				break
			end
		end
		SetGlobal2Vector("ws_flag_zone_" .. t, at)
	end
end

-- Carrying the flag -------------------------------------------------------------------

-- TF2 straps the case to its players' "flag" attachment; HL2's skeletons
-- have none, so it rides their upper spine (CARRY_BONE), upright on the
-- carrier's back BACK_DEPTH behind the bone, its flat face outward, and
-- moves with the body (CarryBone). A carrier without that bone carries it
-- at CARRY_OFFSET from its origin.
local CARRY_BONE, BACK_DEPTH = "ValveBiped.Bip01_Spine2", 10

-- The carry bone of each model, looked up once (false: the model has none):
-- a player's as it spawns, any other carrier's model the first time it
-- carries.
local carryBones = {}

local function CarryBone(carrier)
	local model = carrier:GetModel()
	if carryBones[model] == nil then carryBones[model] = carrier:LookupBone(CARRY_BONE) or false end
	return carryBones[model] or nil
end

hook.Add("PlayerSpawn", THINK_HOOK, function(ply)
	timer.Simple(0, function() if IsValid(ply) then CarryBone(ply) end end) -- once its model is set
end)

local function Carry(ent, carrier)
	local bone = CarryBone(carrier)
	if not bone then
		ent:SetParent(carrier)
		ent:SetLocalPos(CARRY_OFFSET)
		ent:SetLocalAngles(angle_zero)
		return
	end
	carrier:SetupBones()
	local bonePos, boneAng = carrier:GetBonePosition(bone)
	local forward = carrier:GetForward()
	-- the case's long side up, its thin side facing back
	local pos, ang = bonePos - forward * BACK_DEPTH, carrier:GetUp():AngleEx(-forward)
	ent:FollowBone(carrier, bone)
	local localPos, localAng = WorldToLocal(pos, ang, bonePos, boneAng)
	ent:SetLocalPos(localPos)
	ent:SetLocalAngles(localAng)
end

-- On the ground under where the carrier stood.
local function PutDown(ent, at)
	ent:SetParent(NULL)
	local tr = util.TraceLine({
		start = at + DROP_LIFT,
		endpos = at + DROP_TRACE,
		mask = MASK_SOLID_BRUSHONLY,
	})
	ent:SetPos(tr.Hit and tr.HitPos or at)
	ent:SetAngles(Angle(0, ent:GetAngles().y, 0))
end

local function GoHome(ent)
	ent:SetParent(NULL)
	ent:SetPos(ent.wsHome)
	ent:SetAngles(ent.wsHomeAngles)
end

-- What the flag's events do -------------------------------------------------------------

local function FireOutputs(ent, e, activator)
	ent:TriggerOutput(FLAG_OUTPUTS[e.kind], activator)
	local teamOutput = FLAG_TEAM_OUTPUTS[e.kind]
	if teamOutput and TEAM_OUTPUT[e.team] then ent:TriggerOutput(teamOutput .. TEAM_OUTPUT[e.team], activator) end
end

-- tf_flag_caplimit's win: a full reset, no team switch, the round scored.
local FORCE_MAP_RESET, SWITCH_TEAMS, DONT_ADD_SCORE = true, false, false

local function Score(self, team)
	local won = self.tally:Capture(team, caplimit:GetInt())
	PublishTally(self)
	if won then
		self.rounds:SetWinningTeam(team, Rounds.WINREASON.FLAG_CAPTURE_LIMIT, FORCE_MAP_RESET, SWITCH_TEAMS, DONT_ADD_SCORE)
	end
end

local function Apply(self, ent, events, activator)
	local flag = self.flags[ent]
	local mode = Mode()
	for _, e in ipairs(events) do
		if e.kind == Flag.PICKUP then
			Carry(ent, flag:Carrier())
		elseif e.kind == Flag.DROP then
			PutDown(ent, activator:GetPos())
		else
			GoHome(ent)
		end
		FireOutputs(ent, e, activator)
		if mode.FLAG_CAPS_SCORE then
			for _, line in ipairs(Flag.Lines(e)) do WS.BroadcastSound(line.team, line.sound) end
			if e.kind == Flag.CAPTURE then Score(self, e.team) end
		end
	end
	PublishFlag(ent, flag)
end

-- Binding -----------------------------------------------------------------------------

-- kv = { team, returnTime, disabled }.
function Controller:BindFlag(ent, kv)
	ent.wsHome, ent.wsHomeAngles = ent:GetPos(), ent:GetAngles()
	self.flags[ent] = Flag.New(kv)
	PublishFlag(ent, self.flags[ent])
end

-- tf_flag_caplimit: the captures that win (0: none).
function Controller:CapLimit() return caplimit:GetInt() end

function Controller:UnbindFlag(ent)
	self.flags[ent] = nil
end

-- kv = { team, disabled }.
function Controller:BindZone(ent, kv)
	self.zones[ent] = {
		team = kv.team,
		enabled = not kv.disabled,
	}
end

function Controller:UnbindZone(ent)
	self.zones[ent] = nil
end

-- Inputs ------------------------------------------------------------------------------

local FLAG_INPUTS = {
	enable = function(flag) return flag:SetEnabled(true) end,
	disable = function(flag) return flag:SetEnabled(false) end,
	forcedrop = function(flag) return flag:Drop(CurTime()) end,
	forcereset = function(flag) return flag:Reset(false) end,
	forceresetsilent = function(flag) return flag:Reset(true) end,
	forceresetanddisablesilent = function(flag) return flag:SetEnabled(false) end,
	setteam = function(flag, value)
		flag:SetTeam(tonumber(value) or NOBODY)
		return {}
	end,
	setreturntime = function(flag, value)
		flag:SetReturnTime(tonumber(value) or Flag.RETURN_TIME_DEFAULT)
		return {}
	end,
}

-- Whether the flag took the input.
function Controller:FlagInput(ent, name, value, activator)
	local handler = FLAG_INPUTS[name]
	if not handler then return false end
	local flag = self.flags[ent]
	local carrier = flag:Carrier()
	local events = handler(flag, value)
	Apply(self, ent, events, IsValid(carrier) and carrier or activator)
	if name == "setteam" then ent:SetSkin(ent:WsSkin(flag:Team())) end
	return true
end

local ZONE_INPUTS = {
	enable = function(zone) zone.enabled = true end,
	disable = function(zone) zone.enabled = false end,
	setteam = function(zone, value) zone.team = tonumber(value) or NOBODY end,
}

function Controller:ZoneInput(ent, name, value)
	local handler = ZONE_INPUTS[name]
	if not handler then return false end
	handler(self.zones[ent], value)
	return true
end

-- Thinking ----------------------------------------------------------------------------

local function Alive(ent)
	if not IsValid(ent) then return false end
	if ent:IsPlayer() then return WS.IsAliveInGame(ent) end
	return ent:Health() > 0
end

-- The players and team members standing on the flag or in the zone.
local function Inside(ent)
	local inside = WS.PlayersInside(ent)
	for _, member in ipairs(WS.MembersInside(ent)) do inside[#inside + 1] = member end
	return inside
end

local function Contains(list, ent)
	for _, e in ipairs(list) do
		if e == ent then return true end
	end
	return false
end

local function ZoneFor(self, carrier, team)
	for ent, zone in pairs(self.zones) do
		if zone.enabled and Flag.MayCapture(zone.team, team) and Contains(Inside(ent), carrier) then return ent end
	end
	return nil
end

-- Whether carrier stands in an active respawn room the flag drops in
-- (Flag.DropsIn: its own team's, unless it is MvM's invaders').
local function InOwnRespawnRoom(carrier, team, invaders)
	local point = carrier:WorldSpaceCenter()
	for _, room in ipairs(ents.FindByClass("func_respawnroom")) do
		if room.active and Flag.DropsIn(room.team, team, invaders) and room:PointIsWithin(point) then return true end
	end
	return false
end

local function ThinkFlag(self, ent, flag, now, q)
	local carrier = flag:Carrier()
	if flag:State() == Flag.CARRIED then
		if not Alive(carrier) or WS.TeamNumber(carrier) ~= flag:CarrierTeam() then
			Apply(self, ent, flag:Drop(now), IsValid(carrier) and carrier or ent)
			return
		end
		if InOwnRespawnRoom(carrier, flag:CarrierTeam(), q.invaders) then
			Apply(self, ent, flag:Drop(now), carrier)
			return
		end
		local zone = ZoneFor(self, carrier, flag:CarrierTeam())
		if not zone then return end
		local events = flag:Capture(self.zones[zone].team)
		Apply(self, ent, events, carrier)
		local team = TEAM_OUTPUT[events[1].team]
		zone:TriggerOutput("OnCapture", carrier)
		if team then zone:TriggerOutput("OnCap" .. team, carrier) end
		return
	end
	Apply(self, ent, flag:Think(now), ent)
	for _, candidate in ipairs(Inside(ent)) do
		local events = flag:PickUp(candidate, WS.TeamNumber(candidate), q)
		if #events > 0 then
			Apply(self, ent, events, candidate)
			return
		end
	end
end

-- What the mode lets a carrier do now (Flag:PickUp's q), and whose spawn
-- rooms keep the flag (MvM's invaders).
function Controller:Rules()
	local mode = Mode()
	return {
		ownersCarry = mode.FLAG_OWNERS_CARRY,
		mayBeCapped = Flag.MayBeCapped(self.rounds:State(), self.rounds:InSetup(), mode.FLAG_WAITS_FOR_WAVE),
		invaders = mode.FLAG_INVADERS,
	}
end

-- CCaptureFlag::PickUp from outside the touch (CTFBotFetchFlag giving a
-- robot that just spawned the bomb): carrier takes the flag if the rules
-- let it. Returns whether it did.
function Controller:Give(ent, carrier)
	local events = self.flags[ent]:PickUp(carrier, WS.TeamNumber(carrier), self:Rules())
	if #events == 0 then return false end
	Apply(self, ent, events, carrier)
	return true
end

function Controller:Think(now)
	local q = self:Rules()
	for ent, flag in pairs(self.flags) do
		if IsValid(ent) then ThinkFlag(self, ent, flag, now, q) end
	end
	PublishTally(self)
	PublishZones(self)
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if now < Controller.nextThink then return end
	Controller.nextThink = now + THINK_INTERVAL
	Controller:Think(now)
end)

-- A carrier removed (a disconnect, a soldier's corpse cleaned up) drops the
-- flag before it would go with them.
hook.Add("EntityRemoved", THINK_HOOK, function(ent)
	for flagEnt, flag in pairs(Controller.flags) do
		if flag:Carrier() == ent and IsValid(flagEnt) then Apply(Controller, flagEnt, flag:Drop(CurTime()), ent) end
	end
end)

-- Each round counts its own captures.
Controller.rounds:AddRoundListener(Rounds.PHASE_SPAWN, Rounds.LISTEN_LOGIC, function()
	Controller.tally:Reset()
	PublishTally(Controller)
end)

return Controller
