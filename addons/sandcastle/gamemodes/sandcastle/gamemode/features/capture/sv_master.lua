-- Part of the capture controller (sv.lua): the master, its mini-rounds, the
-- rounds controller's objective port, and tf_logic_cp_timer.
local Controller, Team, Points = ...
local Master = WS.require("games.gameplay.capture.master")
local Rounds = WS.require("games.gameplay.rounds")
local PointByName, RoundSpecs, DeclareWinner = Points.PointByName, Points.RoundSpecs, Points.DeclareWinner

local NOBODY = WS.TEAM_UNASSIGNED

-- The master ---------------------------------------------------------------------------

-- InternalSetWinner: team 0 is a stalemate.
local function SetWinner(self, team)
	local args = self.master:SetWinnerArgs(team, self:Set())
	if args.stalemate then
		self.rounds:SetStalemate(Rounds.STALEMATE.TIMER, args.forceMapReset, false)
		return
	end
	DeclareWinner(self, team, nil, args.forceMapReset, args.switchTeams)
end

-- InputSetWinnerAndForceCaps: the winner takes every point in play.
local function SetWinnerAndForceCaps(self, team)
	for _, point in ipairs(self.master:ForcedCaps(self:Set())) do self:ForceOwner(point, team) end
	SetWinner(self, team)
end

-- The rounds controller's objective port (Rounds.OBJECTIVE_METHODS).
local Objective = {}

function Objective:PlayingMiniRounds() return Controller.master:PlayingMiniRounds() end
function Objective:NumPlayable() return Controller.master:NumPlayable(Controller:Set()) end
function Objective:PlayAllRounds() return Controller.master:PlayAllRounds() end
function Objective:RoundsRemaining(team) return Controller.master:RoundsRemaining(team, Controller:Set()) end
function Objective:ScorePerRound() return not Controller.master:ScorePerCapture() end
function Objective:SuddenDeathWin(team) SetWinnerAndForceCaps(Controller, team) end

-- g_hControlPointMasters[0]: the first master bound is the one in charge.
function Controller:BindMaster(ent, kv)
	if IsValid(self.masterEnt) and self.masterEnt ~= ent then return end
	self.masterEnt = ent
	self.master = Master.New({
		restrict = Team(kv.cpm_restrict_team_cap_win),
		switchTeams = kv.switch_teams == "1",
		scoreStyle = tonumber(kv.score_style) or Master.SCORE_PER_ROUND,
		playAllRounds = kv.play_all_rounds == "1",
		partialCapRate = tonumber(kv.partial_cap_points_rate) or 0,
		capLayout = kv.caplayout or "",
		disabled = kv.startdisabled == "1",
		rounds = RoundSpecs(self),
	})
	self.rounds:SetObjective(Objective)
end

-- A map reset removes the master before its replacement binds.
function Controller:UnbindMaster(ent)
	if ent ~= self.masterEnt then return end
	self.masterEnt = NULL
	self.master = nil
	self.rounds:SetObjective(Rounds.NO_OBJECTIVE)
end

local MASTER_INPUTS = {
	enable = function(self) self.master:Enable() end,
	disable = function(self) self.master:Disable() end,
	setwinner = function(self, value) SetWinner(self, Team(value)) end,
	setwinnerandforcecaps = function(self, value) SetWinnerAndForceCaps(self, Team(value)) end,
	roundspawn = function(self) self:RoundSpawn() end,
	roundactivate = function(self) self:RoundActivate() end,
	setcaplayout = function(self, value) self.master:SetCapLayout(tostring(value)) end,
	-- The HUD's icons are drawn in rows, not at custom positions.
	setcaplayoutcustompositionx = function() end,
	setcaplayoutcustompositiony = function() end,
}

-- Whether the master took the input.
function Controller:MasterInput(ent, name, value)
	local handler = MASTER_INPUTS[name]
	if not handler or ent ~= self.masterEnt then return false end
	handler(self, value)
	return true
end

-- team_control_point_round: cpr_cp_names, cpr_priority,
-- cpr_restrict_team_cap_win, cpr_printname.
function Controller:BindRound(ent, kv)
	self.roundEnts[ent] = {
		pointNames = string.Explode("%s+", string.Trim(kv.cpr_cp_names or ""), true),
		priority = tonumber(kv.cpr_priority) or 0,
		restrict = Team(kv.cpr_restrict_team_cap_win),
		printName = kv.cpr_printname or "",
	}
	if self.master then self.master:SetRounds(RoundSpecs(self)) end
end

function Controller:UnbindRound(ent)
	self.roundEnts[ent] = nil
end

-- Enable and Disable are accepted but not consulted (IsPlayable ignores
-- StartDisabled, as in the SDK); the point list is found by name on use.
local ROUND_INPUTS = {
	enable = function() end,
	disable = function() end,
	roundspawn = function() end,
}

function Controller:RoundInput(ent, name, value)
	local handler = ROUND_INPUTS[name]
	if not handler then return false end
	handler(self, ent, value)
	return true
end

-- tf_logic_cp_timer (CCPTimerLogic) -------------------------------------------------------
-- Loaded with the first timer: its model, its round-spawn listener and its
-- hold on the round timer.

local POINT_TIMER_MODEL = "games.gameplay.capture.point_timer"
local POINT_TIMER_HOLD = "cp_timer"
local POINT_TIMER_MISSING = "%s failed to find control point named '%s'"

-- The model's events, by kind: the entity's output and the HUD's countdown
-- (ObjectiveResource()->SetCPTimerTime).
local function PointTimerEvents(PointTimer)
	return {
		[PointTimer.START] = function(self, ent, point, e)
			ent:TriggerOutput("OnCountdownStart", ent)
			self:SetPointTimer(point, e.endTime)
		end,
		[PointTimer.END] = function(self, ent, point)
			ent:TriggerOutput("OnCountdownEnd", ent)
			self:SetPointTimer(point, nil)
		end,
	}
end

-- CCPTimerLogic::InputRoundSpawn: the point again, since a map reset
-- recreates the points.
local function FindTimerPoint(ent, t)
	if t.pointName == "" then return end
	t.point = PointByName(t.pointName)
	if not IsValid(t.point) then print(string.format(POINT_TIMER_MISSING, ent:GetClass(), t.pointName)) end
end

local function PointTimersRoundSpawn()
	for ent, t in pairs(Controller.cpTimers) do
		if IsValid(ent) then FindTimerPoint(ent, t) end
	end
end

-- CTFGameRules::TimerMayExpire over m_CPTimerEnts.
local function PointTimersHold()
	for ent, t in pairs(Controller.cpTimers) do
		if IsValid(ent) and IsValid(t.point) and not t.model:MayExpire(Controller:TeamMayCapture(t.point, t.model:Team())) then
			return true
		end
	end
	return false
end

-- kv = { controlpoint, timer_length, team_number }.
function Controller:BindPointTimer(ent, kv)
	local PointTimer = WS.require(POINT_TIMER_MODEL)
	self.pointTimerEvents = self.pointTimerEvents or PointTimerEvents(PointTimer)
	self.pointTimerThinkTime = PointTimer.THINK_INTERVAL
	self.cpTimers[ent] = {
		model = PointTimer.New({
			length = tonumber(kv.timer_length),
			team = tonumber(kv.team_number),
		}),
		pointName = kv.controlpoint or "",
		point = NULL,
	}
	self.rounds:AddRoundListener(Rounds.PHASE_SPAWN, Rounds.LISTEN_LOGIC, PointTimersRoundSpawn)
	self.rounds:AddTimerHold(POINT_TIMER_HOLD, PointTimersHold)
end

function Controller:UnbindPointTimer(ent)
	self.cpTimers[ent] = nil
end

-- CCPTimerLogic::Think, only while the timer has its point; returns when
-- the entity thinks next.
function Controller:PointTimerThink(ent)
	local t = self.cpTimers[ent]
	local now = CurTime()
	if IsValid(t.point) then
		local events = t.model:Think(now, {
			teamMayCapture = self:TeamMayCapture(t.point, t.model:Team()),
			capping = self:CappingTeam(t.point) ~= NOBODY,
			roundWon = self.rounds:State() == WS.STATE.TEAM_WIN,
		})
		for _, e in ipairs(events) do self.pointTimerEvents[e.kind](self, ent, t.point, e) end
	end
	return now + self.pointTimerThinkTime
end

-- The timer's inputs, lower-cased: only RoundSpawn.
function Controller:PointTimerInput(ent, name)
	if name ~= "roundspawn" then return false end
	FindTimerPoint(ent, self.cpTimers[ent])
	return true
end
