-- team_control_point_master: chooses the mini-round to play and declares a
-- round won when one team owns every point in play (CTeamControlPointMaster,
-- team_control_point_master.cpp). Without team_control_point_rounds every
-- control point is in play.
ENT.Type = "point"
ENT.Base = "base_point"

-- score_style: a team scores per round won, or per point captured.
local SCORE_PER_ROUND, SCORE_PER_CAPTURE = 0, 1

local KEYS = {
	cpm_restrict_team_cap_win = function(self, v) self.restrictTeam = tonumber(v) or WETSAND.TEAM_UNASSIGNED end,
	switch_teams = function(self, v) self.switchTeams = v == "1" end,
	score_style = function(self, v) self.scoreStyle = tonumber(v) or SCORE_PER_ROUND end,
	play_all_rounds = function(self, v) self.playAllRounds = v == "1" end,
	partial_cap_points_rate = function(self, v) self.partialCapRate = tonumber(v) or 0 end,
	startdisabled = function(self, v) self.disabled = v == "1" end,
	caplayout = function(self, v) self.capLayout = v end,
}

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if KEYS[k] then
		KEYS[k](self, value)
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.restrictTeam = self.restrictTeam or WETSAND.TEAM_UNASSIGNED
	self.switchTeams = self.switchTeams or false
	self.scoreStyle = self.scoreStyle or SCORE_PER_ROUND
	self.playAllRounds = self.playAllRounds or false
	self.partialCapRate = self.partialCapRate or 0
	self.disabled = self.disabled or false
	self.current = NULL
	self.firstRoundAfterRestart = true
	self:FindRounds()
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:IsActive()
	return not self.disabled
end

-- Rounds --------------------------------------------------------------------------------

function ENT:FindRounds()
	self.rounds = ents.FindByClass("team_control_point_round")
end

function ENT:PlayingMiniRounds()
	return #self.rounds > 0
end

function ENT:CurrentRound()
	return self.current
end

function ENT:ScorePerCapture()
	return self.scoreStyle == SCORE_PER_CAPTURE
end

function ENT:IsInRound(point)
	if self:PlayingMiniRounds() and IsValid(self.current) then return self.current:HasPoint(point) end
	return true
end

function ENT:RoundInfos()
	local infos = {}
	for i, r in ipairs(self.rounds) do
		infos[i] = { name = r:GetName(), priority = r.priority, playable = r:IsPlayable() }
	end
	return infos
end

function ENT:NumPlayable()
	return WETSAND.RoundsLib.PlayableCount(self:RoundInfos())
end

-- The stage of a multi-stage map for the HUD: the current round's place in
-- priority order.
function ENT:PublishStage()
	local stage, name = 0, ""
	if IsValid(self.current) then
		for i, r in ipairs(self.rounds) do
			if r == self.current then stage = WETSAND.RoundsLib.StageOf(self:RoundInfos(), i) end
		end
		name = self.current.printName
	end
	SetGlobal2Int("wetsand_mini_round_stage", stage)
	SetGlobal2Int("wetsand_mini_round_count", #self.rounds)
	SetGlobal2String("wetsand_mini_round_name", name)
end

-- GetControlPointRoundToPlay and RegisterRoundBeingPlayed. The gamerules
-- remember the rounds played (CTeamplayRoundBasedRules::AddPlayedRound).
function ENT:ChooseRound()
	local rules = WETSAND.Rules
	local history = {
		previous = rules.previousRounds,
		first = rules.firstRoundPlayed,
		firstAfterRestart = self.firstRoundAfterRestart,
	}
	local i = WETSAND.RoundsLib.ChooseRound(self:RoundInfos(), history, math.random)
	if not i then
		self.current = NULL
		self:PublishStage()
		return
	end
	self.current = self.rounds[i]
	local name = self.current:GetName()
	rules:AddPlayedRound(name)
	if self.firstRoundAfterRestart then
		rules.firstRoundPlayed = name
		self.firstRoundAfterRestart = false
	end
	self:PublishStage()
	self.current:FireOnStart()
	hook.Run("WetsandMiniRoundStart", self.current)
end

-- CTeamControlPointMaster::InputRoundSpawn
function ENT:RoundSpawn()
	self:FindRounds()
end

-- CTeamControlPointMaster::InputRoundActivate
function ENT:RoundActivate()
	if self:PlayingMiniRounds() and not IsValid(self.current) then self:ChooseRound() end
	self:PublishStage()
end

-- Called by the gamerules as the next round begins (PreviousRoundEnd).
function ENT:FireRoundEndOutput()
	if not IsValid(self.current) then return end
	self.current:FireOnEnd()
	self.current = NULL
end

-- Winning ---------------------------------------------------------------------------------

local function PointStates(points, override, overrideTeam)
	local states = {}
	for i, p in ipairs(points) do
		states[i] = { owner = p == override and overrideTeam or WETSAND.CapTeam(p), group = WETSAND.PointGroup(p) }
	end
	return states
end

-- CTeamControlPointMaster::WouldNewCPOwnerWinGame (over every point).
function ENT:WouldNewOwnerWin(point, team)
	local points = WETSAND.ControlPoints()
	return WETSAND.RoundsLib.TeamOwnsAllPoints(PointStates(points, point, team)) == team
end

function ENT:FireTeamWinOutput(team)
	self:TriggerOutput(team == WETSAND.TEAM_RED and "OnWonByTeam1" or "OnWonByTeam2", self)
end

-- A mini-round win resets the map only when no playable round is left, and
-- only that final win switches teams.
function ENT:DeclareWinner(team)
	local forceMapReset = true
	if self:PlayingMiniRounds() then forceMapReset = self:NumPlayable() == 0 end
	WETSAND.Rules:SetWinningTeam(team, WETSAND.RoundsLib.WINREASON.ALL_POINTS_CAPTURED, forceMapReset, forceMapReset and self.switchTeams)
	self:FireTeamWinOutput(team)
end

-- CTeamControlPointMaster::CheckWinConditions
function ENT:CheckWinConditions()
	if self.disabled or not IsValid(WETSAND.Rules) then return end
	local winner
	if self:PlayingMiniRounds() then
		if not IsValid(self.current) then return end
		winner = self.current:CheckWinConditions()
	else
		winner = WETSAND.RoundsLib.RoundWinner(self.restrictTeam, PointStates((WETSAND.ControlPoints())))
	end
	if winner then self:DeclareWinner(winner) end
end

-- CPMThink
function ENT:Think()
	self:NextThink(CurTime() + 0.2)
	if IsValid(WETSAND.Rules) and WETSAND.Rules:PointsMayBeCaptured() then self:CheckWinConditions() end
	return true
end

-- CTeamControlPointMaster::InternalSetWinner: team 0 is a stalemate.
function ENT:SetWinner(team)
	if team == WETSAND.TEAM_UNASSIGNED then
		local forceMapReset = not self:PlayingMiniRounds() or self:NumPlayable() == 0
		WETSAND.Rules:SetStalemate(WETSAND.RoundsLib.STALEMATE.TIMER, forceMapReset)
		return
	end
	self:DeclareWinner(team)
end

-- InputSetWinnerAndForceCaps: the survivors of sudden death take every point in play.
function ENT:SetWinnerAndForceCaps(team)
	for _, point in ipairs(WETSAND.ControlPoints()) do
		if self:IsInRound(point) then WETSAND.ForcePointOwner(point, team) end
	end
	self:SetWinner(team)
end

-- The rounds a team still has to win to take every point (CalcNumRoundsRemaining).
function ENT:RoundsRemaining(team)
	local points, rankOf = WETSAND.ControlPoints()
	local states = {}
	for i, p in ipairs(points) do states[i] = { owner = WETSAND.CapTeam(p) } end
	local rounds = {}
	for i, r in ipairs(self.rounds) do
		local indices = {}
		for _, p in ipairs(r:Points()) do indices[#indices + 1] = rankOf[p] + 1 end
		rounds[i] = { restrict = r.restrictTeam, points = indices }
	end
	return WETSAND.RoundsLib.RoundsRemaining(team, rounds, states)
end

local INPUTS = {
	enable = function(self) self.disabled = false end,
	disable = function(self) self.disabled = true end,
	setwinner = function(self, value) self:SetWinner(tonumber(value) or WETSAND.TEAM_UNASSIGNED) end,
	setwinnerandforcecaps = function(self, value) self:SetWinnerAndForceCaps(tonumber(value) or WETSAND.TEAM_UNASSIGNED) end,
	roundspawn = function(self) self:RoundSpawn() end,
	roundactivate = function(self) self:RoundActivate() end,
	-- The HUD here lays points out along the cart track.
	setcaplayout = function(self, value) self.capLayout = value end,
	setcaplayoutcustompositionx = function() end,
	setcaplayoutcustompositiony = function() end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
