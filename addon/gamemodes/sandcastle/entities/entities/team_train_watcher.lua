-- team_train_watcher (CTeamTrainWatcher, team_train_watcher.cpp): follows a
-- payload train along its path_track chain. It measures progress for the
-- HUD, warns as the train nears each checkpoint, sounds the capture alarm
-- near the goal, holds the round timer while the cart is contested, and
-- with handle_train_movement drives the train itself (speed by pushers,
-- hills, receding). With handle_train_movement 0 the map moves the train
-- from the capture area's outputs and the watcher only tracks it.
-- The decisions live in foundation/payload.lua (WETSAND.Payload).
ENT.Type = "point"
ENT.Base = "base_point"

local recede_time = CreateConVar("tf_escort_recede_time", "30", 0, "Seconds without pushers before the cart recedes.", 0)
local recede_time_overtime = CreateConVar("tf_escort_recede_time_overtime", "5", 0, "Seconds without pushers before the cart recedes in overtime.", 0)

local SF_PATH_UPHILL, SF_PATH_DOWNHILL = 0x20, 0x40
local MAX_LINKS = 8
local P

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	self.wetsandKv = self.wetsandKv or {}
	self.wetsandKv[k] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Key(name, default)
	local v = (self.wetsandKv or {})[name]
	if v == nil or v == "" then return default end
	return v
end

local function Flag(value)
	return value ~= "0" and value ~= "false"
end

function ENT:Initialize()
	P = WETSAND.Payload
	self.capture = WETSAND.Feature("capture")
	WETSAND.HoldTimersForWatchers()
	self.disabled = self:Key("startdisabled", "0") == "1"
	self.team = tonumber(self:Key("teamnum", WETSAND.TEAM_BLUE)) or WETSAND.TEAM_BLUE
	self.handleMovement = self:Key("handle_train_movement", "0") == "1"
	self.canRecede = Flag(self:Key("train_can_recede", "1"))
	self.trainRecedeTime = tonumber(self:Key("train_recede_time", 0)) or 0
	self.forwardModifier = tonumber(self:Key("speed_forward_modifier", 1)) or 1
	self.levels = {
		tonumber(self:Key("hud_min_speed_level_1", 30)) or 30,
		tonumber(self:Key("hud_min_speed_level_2", 60)) or 60,
		tonumber(self:Key("hud_min_speed_level_3", 90)) or 90,
	}
	self.numCappers = 0
	self.currentSpeed = 0
	self.hill = P.HILL_NONE
	self.receding = false
	self.waitingToRecede = false
	self.recedeAt = 0
	self.capBlocked = false
	self.speedLevel = 0
	self.alarm = P.NewAlarm()
	self.activated = false
	self.subscribed = {}
	-- path_track OnPass reaches the watcher by name, so a nameless one gets one
	if self:GetName() == "" then self:SetName("wetsand_train_watcher_" .. self:EntIndex()) end
	hook.Add("WetsandRoundActive", self, self.RoundActivate)
	hook.Add("WetsandOvertime", self, self.OnOvertime)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:OnRemove()
	self:StopCaptureAlarm()
end

-- Path -----------------------------------------------------------------------------

local function HillType(node)
	local flags = tonumber(WETSAND.KeyValues(node).spawnflags) or 0
	if bit.band(flags, SF_PATH_UPHILL) ~= 0 then return P.HILL_UP end
	if bit.band(flags, SF_PATH_DOWNHILL) ~= 0 then return P.HILL_DOWN end
	return P.HILL_NONE
end

local function NextNode(node)
	return WETSAND.FindByName(WETSAND.KeyValues(node).target)
end

-- The chain from start_node to goal_node (or its dead end), with the path
-- length to each node.
function ENT:BuildPath()
	local goal = WETSAND.FindByName(self:Key("goal_node"))
	self.nodes, self.nodeIndex, self.distanceAt = {}, {}, {}
	local node, total = WETSAND.FindByName(self:Key("start_node")), 0
	while IsValid(node) and not self.nodeIndex[node] do
		local i = #self.nodes + 1
		if i > 1 then total = total + node:GetPos():Distance(self.nodes[i - 1]:GetPos()) end
		self.nodes[i], self.nodeIndex[node], self.distanceAt[i] = node, i, total
		if node == goal then break end
		node = NextNode(node)
	end
	-- the SDK asserts on an empty path and measures against 1
	self.total = total > 0 and total or 1
end

-- Checkpoints: linked_pathtrack_N with linked_cp_N; a track off the path counts as the start.
function ENT:BuildLinks()
	self.links = {}
	for n = 1, MAX_LINKS do
		local track = WETSAND.FindByName(self:Key("linked_pathtrack_" .. n))
		local cp = WETSAND.FindByName(self:Key("linked_cp_" .. n))
		if IsValid(track) and IsValid(cp) then
			local i = self.nodeIndex[track]
			self.links[#self.links + 1] = { cp = cp, distance = i and self.distanceAt[i] or 0, index = i, alerted = false }
			-- the cart's bar shows its points, so the point HUD leaves them out
			self.capture:SetHudHidden(cp, true)
		end
	end
end

function ENT:BuildHills()
	local data = {}
	for i, node in ipairs(self.nodes) do
		data[i] = { distance = self.distanceAt[i], hill = HillType(node) }
	end
	self.hills = P.HillSegments(data, self.total)
end

-- The node at the back of the segment the train is on (its m_ppath), found
-- once by projecting the train onto the path (ProjectPointOntoPath); OnPass
-- keeps it current from then on.
function ENT:NearestPathIndex()
	local pos, best, bestDist = self.train:GetPos(), 1, math.huge
	for i = 1, #self.nodes - 1 do
		local a, b = self.nodes[i]:GetPos(), self.nodes[i + 1]:GetPos()
		local ab = b - a
		local t = math.Clamp((pos - a):Dot(ab) / math.max(ab:LengthSqr(), 1), 0, 1)
		local d = pos:DistToSqr(a + ab * t)
		if d < bestDist then best, bestDist = i, d end
	end
	return best
end

function ENT:SubscribePath()
	for _, node in ipairs(self.nodes) do
		if not self.subscribed[node] then
			self.subscribed[node] = true
			node:Fire("AddOutput", "OnPass " .. self:GetName() .. ":WetsandPathPassed::0:-1")
		end
	end
end

-- Links the capture area riding the train, so it reports its cappers here.
function ENT:ClaimCaptureArea()
	for _, area in ipairs(ents.FindByClass("trigger_capture_area")) do
		if area:GetParent() == self.train then
			area:SetTrainWatcher(self)
			return
		end
	end
end

-- WatcherActivate
function ENT:WatcherActivate()
	self.recedeAt = 0
	self.waitingToRecede = false
	self.capBlocked = false
	self.area = nil
	self.distanceFromStart = 0
	self:StopCaptureAlarm()
	self.alarm = P.NewAlarm()
	self.train = WETSAND.FindByName(self:Key("train"))
	self.advanceTo = nil
	self:BuildPath()
	self:BuildLinks()
	self:BuildHills()
	self:SubscribePath()
	if IsValid(self.train) then
		if self.handleMovement then self:ClaimCaptureArea() end
		self.pathIndex = self:NearestPathIndex()
	end
	self:InternalSetSpeedForwardModifier(self.forwardModifier)
	self:CaptureMaxSpeed()
	self.activated = true
end

function ENT:RoundActivate()
	self:StopCaptureAlarm()
	if not self.disabled then self:WatcherActivate() end
end

-- Train movement ---------------------------------------------------------------------

function ENT:Sparks(on)
	local name = self:Key("env_spark_name")
	if not name then return end
	for _, spark in ipairs(ents.FindByName(name)) do
		spark:Fire(on and "StartSpark" or "StopSpark")
	end
end

-- HandleTrainMovement
function ENT:HandleTrainMovement(startReceding)
	if self.disabled or not self.handleMovement or not IsValid(self.train) then return end
	local speed, receding = P.TrainSpeed(self, startReceding)
	-- driven on to a checkpoint by an admin, whoever is on it
	if self.advanceTo then speed, receding = 1, false end
	self.receding = receding
	if speed == self.currentSpeed then return end
	self.currentSpeed = speed
	self.train:Fire("SetSpeedDirAccel", tostring(speed))
	self:Sparks(speed < 0)
end

function ENT:InternalSetSpeedForwardModifier(modifier)
	if self.disabled or not self.handleMovement then return end
	self.forwardModifier = math.Clamp(math.abs(modifier), 0, 1)
	if IsValid(self.train) then self.train:Fire("SetSpeedForwardModifier", tostring(self.forwardModifier)) end
end

local function InOvertime()
	return GetGlobal2Bool("wetsand_round_overtime", false)
end

function ENT:StartRecedeCountdown(delay)
	self.waitingToRecede = true
	self.recedeAt = CurTime() + delay
end

-- InternalSetNumTrainCappers: cappers, 0 for none, -1 when blocked.
function ENT:InternalSetNumTrainCappers(num, trigger)
	if self.disabled then return end
	self.numCappers = num
	if IsValid(trigger) and trigger:GetClass() == "trigger_capture_area" then
		self.capBlocked = trigger:IsBlocked()
		self.area = trigger
	end
	if num <= 0 and not self.capBlocked and self.canRecede then
		if not self.waitingToRecede then
			self:StartRecedeCountdown(P.RecedeDelay(InOvertime(), self.trainRecedeTime, recede_time:GetFloat(), recede_time_overtime:GetFloat()))
		end
	else
		self.waitingToRecede = false
		self.recedeAt = 0
	end
	self:HandleTrainMovement()
end

-- Called by the capture area riding the train; only for watchers that move it.
function ENT:SetNumTrainCappers(num, area)
	if self.disabled or not self.handleMovement then return end
	self:InternalSetNumTrainCappers(num, area)
end

-- InputOnStartOvertime, raised by the round timer's WetsandOvertime hook.
function ENT:OnOvertime(active)
	if not active or not self.waitingToRecede then return end
	self.recedeAt = P.OvertimeRecedeAt(self.recedeAt, CurTime(), recede_time_overtime:GetFloat())
end

-- A node of our path fired OnPass: track the train's current node and, when
-- moving it, the hill it is on (the path_track_passed event handler).
function ENT:PathPassed(node, train)
	local i = self.nodeIndex and self.nodeIndex[node]
	if not i or train ~= self.train then return end
	self.pathIndex = P.PassedIndex(i, self.train:GetInternalVariable("m_flSpeed"))
	if self.disabled or not self.handleMovement then return end
	-- receding onto a node whose previous node is disabled: the train stops
	-- here and will not pass it again going forward, so keep the hill state
	if self.receding then
		local prev = self.nodes[i - 1]
		if IsValid(prev) and WETSAND.KeyValues(prev).wetsandDisabled then return end
	end
	local hill = HillType(node)
	local update = hill ~= self.hill
	if not update and self.hill ~= P.HILL_NONE then
		local nextNode = self.currentSpeed < 0 and self.nodes[i - 1] or self.nodes[i + 1]
		if IsValid(nextNode) and HillType(nextNode) ~= self.hill then
			update, hill = true, P.HILL_NONE
		end
	end
	if update then
		self.hill = hill
		self:HandleTrainMovement()
	end
end

-- Admin controls (the Game Rules editor) ----------------------------------------------

-- The map's top speed for the train, read once per train entity (a full
-- reset makes a new one), before any scale is applied to it.
function ENT:CaptureMaxSpeed()
	if not IsValid(self.train) then return end
	if self.speedTrain ~= self.train then
		self.speedTrain = self.train
		self.baseMaxSpeed = self.train:GetInternalVariable("m_maxSpeed")
	end
	self:ApplyMaxSpeed()
end

-- The train's top speed (func_tracktrain's startspeed keyfield, m_maxSpeed,
-- which SetSpeedDirAccel scales) under the admin's cart speed; the watcher
-- then asks for its current speed again so the change shows at once.
function ENT:ApplyMaxSpeed()
	if not IsValid(self.train) or not self.baseMaxSpeed then return end
	local maxSpeed = P.MaxSpeed(self.baseMaxSpeed, WETSAND.CartSpeedScale(), self.advanceTo ~= nil)
	self.train:SetKeyValue("startspeed", tostring(maxSpeed))
	if self.handleMovement and not self.disabled then self.train:Fire("SetSpeedDirAccel", tostring(self.currentSpeed)) end
end

-- Drive the cart at full (and boosted) speed until it passes the next
-- checkpoint's path_track, so the map's own OnPass logic captures it.
-- Returns true, or false and why not.
function ENT:AdvanceToNextCheckpoint()
	if not self:IsActive() or not IsValid(self.train) then return false, "the cart is not active" end
	if not self.handleMovement then return false, "this map moves its cart itself" end
	if WETSAND.State() ~= WETSAND.STATE.RND_RUNNING then return false, "the round is not running" end
	local link = P.NextCheckpoint(self.links, self.distanceFromStart or 0)
	if not link or not link.index then return false, "no checkpoint ahead" end
	self.advanceTo = link
	self:ApplyMaxSpeed()
	self:HandleTrainMovement()
	return true
end

function ENT:CheckAdvance()
	if not self.advanceTo or self.pathIndex < self.advanceTo.index then return end
	self.advanceTo = nil
	self:ApplyMaxSpeed()
	self:HandleTrainMovement()
end

-- Alerts and the capture alarm ---------------------------------------------------------

-- CTFGameRules::PlayTrainCaptureAlert: everyone hears it, while the round runs.
function ENT:PlayCaptureAlert(cp)
	if WETSAND.State() ~= WETSAND.STATE.RND_RUNNING then return end
	local final = self.capture:FinalPointInMap(cp)
	WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, final and "Announcer.Cart.FinalWarning" or "Announcer.Cart.Warning")
end

function ENT:FinalLinkedPoint()
	return self.links[#self.links].cp
end

local ALARM_ACTIONS = {
	-- StartCaptureAlarm: a looping sound on the final point every player hears
	start = function(self)
		local filter = RecipientFilter()
		filter:AddAllPlayers()
		self.alarmSound = CreateSound(self:FinalLinkedPoint(), "Cart.Warning", filter)
		self.alarmSound:Play()
	end,
	stop = function(self)
		if self.alarmSound then
			self.alarmSound:Stop()
			self.alarmSound = nil
		end
	end,
	-- WatcherAlarmThink
	single = function(self)
		self:FinalLinkedPoint():EmitSound("Cart.WarningSingle")
	end,
}

function ENT:RunAlarmActions(actions)
	for _, action in ipairs(actions) do ALARM_ACTIONS[action](self) end
end

function ENT:StopCaptureAlarm()
	self:RunAlarmActions(P.StopAlarm(self.alarm))
end

-- Think --------------------------------------------------------------------------------

function ENT:CheckRecede()
	if not self.waitingToRecede or self.recedeAt >= CurTime() then return end
	self.waitingToRecede = false
	-- the train does not recede in overtime
	if InOvertime() then return end
	self:TriggerOutput("OnTrainStartRecede", self)
	self:HandleTrainMovement(true)
end

function ENT:UpdateSpeedLevel(speed)
	local old = self.speedLevel
	self.speedLevel = P.SpeedLevel(speed, speed, self.levels)
	if self.handleMovement and self.speedLevel == 0 and old ~= 0 then self:Sparks(false) end
end

-- Distance to the goal from the node the train heads for, along the path.
function ENT:UpdateProgress(speed)
	local target = P.TargetIndex(self.pathIndex, speed, #self.nodes)
	local straight = self.nodes[target]:GetPos():Distance(self.train:GetPos())
	self.distanceToGoal = P.DistanceToGoal(self.total, self.distanceAt, target, straight)
	self.progress = P.Progress(self.total, self.distanceToGoal)
	self.distanceFromStart = self.total - self.distanceToGoal
end

-- WatcherThink
function ENT:WatcherThink()
	self:CheckRecede()
	local running = WETSAND.State() == WETSAND.STATE.RND_RUNNING
	if not running then self:StopCaptureAlarm() end
	if not IsValid(self.train) or #self.nodes == 0 then return end
	-- the train's current speed stands in for its desired speed, which
	-- GMod does not expose
	local speed = self.train:GetInternalVariable("m_flSpeed")
	self:UpdateSpeedLevel(speed)
	self:UpdateProgress(speed)
	self:CheckAdvance()
	for _, i in ipairs(P.AlertsDue(self.links, self.distanceFromStart, self.canRecede)) do
		self:PlayCaptureAlert(self.links[i].cp)
	end
	self.trackAlarm = self.distanceToGoal <= P.ALARM_DISTANCE
	self:RunAlarmActions(P.AlarmStep(self.alarm, self.distanceToGoal, running, self.canRecede, #self.links > 0, CurTime()))
end

function ENT:Think()
	self:NextThink(CurTime() + 0.1)
	if self.disabled then return true end
	if not self.activated then self:WatcherActivate() end
	self:WatcherThink()
	return true
end

-- Questions others ask ------------------------------------------------------------------

function ENT:IsActive()
	return not self.disabled and self.activated
end

function ENT:IsWatching(train)
	return IsValid(train) and train == self.train
end

-- Whether this watcher hears from the area (the cart's capture area).
function ENT:UsesArea(area)
	return area == self.area or (IsValid(self.train) and area:GetParent() == self.train)
end

function ENT:Train()
	return self.train
end

-- The path_track chain from start_node to goal_node, as BuildPath found it
-- (a new list each time the watcher activates).
function ENT:PathNodes()
	return self.nodes
end

-- How far along the path the next checkpoint ahead of the cart lies, or nil.
function ENT:NextCheckpointDistance()
	local link = P.NextCheckpoint(self.links or {}, self.distanceFromStart or 0)
	return link and link.distance
end

function ENT:TrainDistanceAlongTrack()
	return self.distanceFromStart or 0
end

-- CTeamTrainWatcher::TimerMayExpire, plus CTFGameRules::TimerMayExpire's
-- hold while a point is being captured, for this cart's own area, so a
-- timer asking only the watchers still runs overtime while the cart is pushed.
function ENT:TimerMayExpire()
	if self.disabled then return true end
	if self.waitingToRecede or self.capBlocked then return false end
	return not (IsValid(self.area) and self.area:IsCapturing())
end

function ENT:HudState()
	local cps, owners = {}, {}
	for i, link in ipairs(self.links) do
		cps[i] = link.distance / self.total
		owners[i] = self.capture:Owner(link.cp)
	end
	return {
		team = self.team,
		progress = self.progress or 0,
		speed = self.speedLevel,
		cappers = self.numCappers,
		recedeAt = self.waitingToRecede and self.recedeAt or 0,
		canRecede = self.canRecede,
		alarm = self.trackAlarm == true,
		cps = cps,
		owners = owners,
		hills = self.hills,
	}
end

-- Inputs ----------------------------------------------------------------------------------

local INPUTS = {
	wetsandpathpassed = function(self, value, activator, caller) self:PathPassed(caller, activator) end,
	roundactivate = function(self) self:RoundActivate() end,
	enable = function(self)
		self:StopCaptureAlarm()
		self.disabled = false
		self:WatcherActivate()
	end,
	disable = function(self)
		self:StopCaptureAlarm()
		self.disabled = true
		self.waitingToRecede = false
		if self.handleMovement then
			self.currentSpeed = 0
			if IsValid(self.train) then self.train:Fire("SetSpeedDirAccel", "0") end
		end
	end,
	setnumtraincappers = function(self, value, activator, caller)
		self:InternalSetNumTrainCappers(tonumber(value) or 0, caller)
	end,
	onstartovertime = function(self) self:OnOvertime(true) end,
	setspeedforwardmodifier = function(self, value) self:InternalSetSpeedForwardModifier(tonumber(value) or 1) end,
	settrainrecedetime = function(self, value) self.trainRecedeTime = math.max(tonumber(value) or 0, 0) end,
	settraincanrecede = function(self, value) self.canRecede = Flag(tostring(value)) end,
	-- restarts a set countdown with the non-overtime length
	settrainrecedetimeandupdate = function(self, value)
		self.trainRecedeTime = math.max(tonumber(value) or 0, 0)
		if self.recedeAt > 0 then
			self.recedeAt = CurTime() + P.RecedeDelay(false, self.trainRecedeTime, recede_time:GetFloat(), 0)
		end
	end,
	setteam = function(self, value) self.team = tonumber(value) or self.team end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value, activator, caller)
	return true
end
