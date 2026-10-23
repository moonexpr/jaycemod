-- The capture feature's controller. It owns the map's PointSet (every
-- team_control_point), the Master (team_control_point_master and its
-- team_control_point_rounds) and an Area model per trigger_capture_area;
-- feeds them the players standing in the areas, the map's inputs and the
-- round's phases; and carries out what they answer: outputs, point models,
-- capture sounds, announcer lines, scoring, and round wins through the
-- rounds controller. It publishes the point HUD (ws_point_*) and each
-- player's capture panel (NW2 ws_capture_point/_reason), and is the
-- rounds controller's objective port.
--
-- team_control_point is GMod's own inert engine class, so its keyvalues are
-- recorded by sv_world and its inputs taken here through AcceptInput.
--
-- This root holds the state, the round phases and the wiring that spans
-- parts; its parts are sv_points (the point set, its queries and changes),
-- sv_master (the master, its rounds and tf_logic_cp_timer), sv_areas (the
-- capture areas), sv_hud (what the HUD and the capture panel show) and
-- sv_snapshot (the controller's state as plain data and back).
local Rounds = gameplay.rounds

local NOBODY, RED, BLUE = WS.TEAM_UNASSIGNED, WS.TEAM_RED, WS.TEAM_BLUE
local GAME_TEAMS = { RED, BLUE }

-- TF2's convars (tf_gamerules.cpp, teamplayroundbased_gamerules.cpp).
local caplinear = CreateConVar("tf_caplinear", "1", FCVAR_REPLICATED, "If set to 1, teams must capture control points linearly.")
local capstyle = CreateConVar("mp_capstyle", "1", FCVAR_REPLICATED, "Sets the style of capture points used. 0 = Fixed players required to cap. 1 = More players cap faster, but longer cap times.")
local blockstyle = CreateConVar("mp_blockstyle", "1", FCVAR_REPLICATED, "Sets the style of capture point blocking used. 0 = Blocks break captures completely. 1 = Blocks only pause captures.")
local capdeteriorate = CreateConVar("mp_capdeteriorate_time", "90.0", FCVAR_REPLICATED, "Time it takes for a full capture point to deteriorate.")

local UNLOCK_THINK_TIME = 0.1 -- CONTROL_POINT_UNLOCK_THINK
local MASTER_THINK_TIME = 0.2 -- CPMThink
local PUBLISH_INTERVAL = 0.1 -- the HUD's 10 Hz

local Controller = {
	AREA_THINK_TIME = 0.1, -- AREA_THINK_TIME: each trigger_capture_area thinks this often
	rounds = WS.Feature("rounds"),
	set = nil,
	masterEnt = NULL,
	master = nil,
	roundEnts = {},
	areas = {},
	hudHidden = {},
	pointTimers = {},
	cpTimers = {}, -- tf_logic_cp_timer entity -> { model, pointName, point }
	loops = {},
	nextUnlock = 0,
	nextMasterThink = 0,
	nextPublish = 0,
	-- pointTimerEvents = nil, -- set by the first BindPointTimer
	-- pointTimerThinkTime = nil,
}

local function Team(value)
	return tonumber(value) or NOBODY
end

-- Parts ------------------------------------------------------------------------------

local Part = WS.FeatureParts(getfenv(1), "capture")
local Points = Part("sv_points", Controller, Team, GAME_TEAMS, caplinear)
local ApplyPointEvents, PublishStage, AnyCapturing = Points.ApplyPointEvents, Points.PublishStage, Points.AnyCapturing
Part("sv_master", Controller, Team, Points)
local AreaPoint = Part("sv_areas", Controller, GAME_TEAMS, capstyle, blockstyle, capdeteriorate, Points)
local PublishPoints, PublishPanels = Part("sv_hud", Controller, capstyle, blockstyle, Points, AreaPoint)
Part("sv_snapshot", Controller, Points)

-- Round phases --------------------------------------------------------------------------

-- InputRoundSpawn: the master finds its points and rounds again.
function Controller:RoundSpawn()
	self:Rebuild()
	PublishStage(self)
end

-- InputRoundActivate: every point (outputs, locks), then the master, which
-- chooses the mini-round and registers it with the gamerules.
function Controller:RoundActivate()
	local set = self:Set()
	ApplyPointEvents(self, set:RoundActivate())
	if self.master then
		local name, firstAfterRestart = self.master:RoundActivate(set, self.rounds:History(), math.random)
		if name then
			self.rounds:AddPlayedRound(name)
			if firstAfterRestart then self.rounds:SetFirstRoundPlayed(name) end
			local roundEnt = self:CurrentRound()
			roundEnt:TriggerOutput("OnStart", roundEnt)
			hook.Run("WSMiniRoundStart", roundEnt)
		end
	end
	PublishStage(self)
end

-- CTFGameRules::PreviousRoundEnd: the mini-round's OnEnd.
function Controller:PreviousRoundEnd()
	if not self.master then return end
	local roundEnt = self:CurrentRound()
	self.master:EndRound()
	if IsValid(roundEnt) then roundEnt:TriggerOutput("OnEnd", roundEnt) end
end

-- Timed unlocks, the master's think and the HUD, on one clock.
hook.Add("Think", "ws_capture", function()
	local self = Controller
	local now = CurTime()
	if now >= self.nextUnlock then
		self.nextUnlock = now + UNLOCK_THINK_TIME
		ApplyPointEvents(self, self:Set():Tick(now, self.rounds:State() == WS.STATE.RND_RUNNING))
	end
	if now >= self.nextMasterThink then
		self.nextMasterThink = now + MASTER_THINK_TIME
		if self.master and self.master:Active() and self.rounds:PointsMayBeCaptured() then self:CheckWinConditions() end
	end
	if now >= self.nextPublish and WS.Active() then
		self.nextPublish = now + PUBLISH_INTERVAL
		PublishPoints(self)
		PublishPanels(self)
	end
end)

-- Wiring into the round -------------------------------------------------------------------

Controller.rounds:AddRoundListener(Rounds.PHASE_SPAWN, Rounds.LISTEN_CAPTURE, function() Controller:RoundSpawn() end)
Controller.rounds:AddRoundListener(Rounds.PHASE_ACTIVATE, Rounds.LISTEN_CAPTURE, function() Controller:RoundActivate() end)
Controller.rounds:AddRoundListener(Rounds.PHASE_ROUND_END, Rounds.LISTEN_CAPTURE, function() Controller:PreviousRoundEnd() end)
Controller.rounds:AddTimerHold("capture", function() return AnyCapturing(Controller) end, true)

-- A cleanup recreates every point, and not every cleanup is a round's (an
-- admin's game.CleanUpMap has no RoundSpawn): the set follows the new ones.
hook.Add("PostCleanupMap", "ws_capture", function() Controller:Rebuild() end)

return Controller
