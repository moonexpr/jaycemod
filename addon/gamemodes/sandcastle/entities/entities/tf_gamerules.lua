-- tf_gamerules: TF2's gamerules proxy, carrying the round-based layer of
-- CTeamplayRoundBasedRules (teamplayroundbased_gamerules.cpp) and the parts of
-- CTFGameRules (tf_gamerules.cpp) that drive rounds: the state machine,
-- mini-rounds, sudden death, scores, respawn waves, and the win, round and
-- time limits. It survives round cleanups, as the gamerules do in TF2.
ENT.Type = "point"
ENT.Base = "base_point"

local S = WETSAND.STATE

-- TF2's own convars, as teamplayroundbased_gamerules.cpp and
-- multiplay_gamerules.cpp define them. GMod's engine may already define some
-- of the multiplay ones; those are used as they are.
local function TF2ConVar(name, ...)
	return GetConVar(name) or CreateConVar(name, ...)
end

local respawnwavetime = TF2ConVar("mp_respawnwavetime", "10.0", { FCVAR_NOTIFY, FCVAR_REPLICATED }, "Time between respawn waves.")
local bonusroundtime = TF2ConVar("mp_bonusroundtime", "15", FCVAR_REPLICATED, "Time after round win until round restarts", 5, 15)
local enableroundwaittime = TF2ConVar("mp_enableroundwaittime", "1", FCVAR_REPLICATED, "Enable timers to wait between rounds.")
local stalemateEnable = TF2ConVar("mp_stalemate_enable", "0", FCVAR_NOTIFY, "Enable/Disable stalemate mode.")
local stalemateTimelimit = TF2ConVar("mp_stalemate_timelimit", "240", FCVAR_REPLICATED, "Timelimit (in seconds) of the stalemate round.")
local winlimit = TF2ConVar("mp_winlimit", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY }, "Max score one team can reach before server changes maps", 0)
local maxrounds = TF2ConVar("mp_maxrounds", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY }, "max number of rounds to play before server changes maps", 0)
local timelimit = TF2ConVar("mp_timelimit", "0", { FCVAR_NOTIFY, FCVAR_REPLICATED }, "game time per map in minutes")
local matchEndAtTimelimit = TF2ConVar("mp_match_end_at_timelimit", "0", FCVAR_NOTIFY, "Allow the match to end when mp_timelimit hits instead of waiting for the end of the current round.")
local chattime = TF2ConVar("mp_chattime", "10", FCVAR_REPLICATED, "amount of time players can chat after the game is over", 1, 120)

-- The pre-round lasts this many seconds times mp_enableroundwaittime. TF2's
-- State_Enter_PREROUND uses 5; Sandcastle uses 3.
local PREROUND_SECONDS = 3

-- GetMinTimeWhenPlayerMaySpawn: 2s death animation plus the freezecam's
-- spec_freeze_traveltime (0.4) and spec_freeze_time (4).
local DEATH_ANIM_LENGTH = 2.0 + 0.4 + 4.0
local OPTIMAL_TEAM_SIZE = 8
local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local WAVE_TIME_UNSET = -1 -- m_TeamRespawnWaveTimes before a map input sets one
local ROLE_NONE = 0 -- TEAM_ROLE_NONE
-- CTFGameRules::GetRespawnWaveMaxLength: small teams never shorten a wave below this.
local MIN_SCALED_WAVE = 5

local TIMELIMIT_TIMER_NAME = "zz_teamplay_timelimit_timer"
local UNSET = -1 -- an admin override not given

-- A full reset keeps the gamerules, as TF2 does, and the admin editors.
local CLEANUP_KEEPS = { "tf_gamerules", "edit_gamerules", "edit_roundtimer" }

local function Lib() return WETSAND.RoundsLib end

function ENT:KeyValue(key, value)
	if string.sub(key, 1, 2) == "On" or string.sub(key, 1, 4) == "Team" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	WETSAND.Rules = self
	SetGlobal2Bool("tf2.active", true)
	self.waveTime = { [RED] = WAVE_TIME_UNSET, [BLUE] = WAVE_TIME_UNSET }
	self.originalWaveTime = { [RED] = WAVE_TIME_UNSET, [BLUE] = WAVE_TIME_UNSET }
	self.nextWave = { [RED] = 0, [BLUE] = 0 }
	self.goalString = {}
	self.role = {}
	self.roundsPlayed = 0
	self.forceMapReset = true
	self.mapFresh = true
	self.switchTeams = false
	self.previousRounds = {}
	self.winningTeam = WETSAND.TEAM_UNASSIGNED
	self.allowStalemateAtTimelimit = false
	self.mapResetTime = CurTime()
	self.nextPeriodic = 0
	self.teamCounts = {}
	-- The Game Rules editor's overrides, kept across rounds.
	self.adminWaveTime = { [RED] = UNSET, [BLUE] = UNSET }
	self.respawnsDisabled = false
	self:StateEnter(S.PREGAME)
end

function ENT:OnRemove()
	if WETSAND.Rules == self then
		WETSAND.Rules = nil
		SetGlobal2Bool("tf2.active", false)
	end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

-- State machine (State_Transition, State_Enter, State_Leave, State_Think) ---------------

local function StateName(state)
	return table.KeyFromValue(S, state)
end

function ENT:StateGet()
	return self.state
end

function ENT:StateEnter(state)
	self.state = state
	self.transitionAt = nil
	SetGlobal2Int("tf2.state", state)
	local enter = self["StateEnter_" .. StateName(state)]
	if enter then enter(self) end
end

function ENT:StateTransition(state)
	local leave = self["StateLeave_" .. StateName(self.state)]
	if leave then leave(self) end
	self:StateEnter(state)
end

-- Stopping the game (the Gameplay Settings' Stop Game): non-gameplay mode,
-- which plays like Sandbox, and TF2's tournament ready-up: the rounds wait
-- in BETWEEN_RNDS with every timer paused, and the state machine thinks no
-- more until a new game (Unhalt, then RestartRound). Setup, if it is on,
-- ends as its clock running out would (team_round_timer's FinishSetup,
-- firing OnSetupFinished), so the map opens its own setup gates. Entering
-- it, as CTFGameRules::BetweenRounds_Start does, fires the map's
-- OnStateEnterBetweenRounds and every tf_logic_competitive's
-- OnSpawnRoomDoorsShouldUnlock, which maps wire to their spawn doors. The
-- spawn doors (func_doors a trigger with a team filter opens) stand open, and the filters and forcefields let
-- everyone through (WETSAND.GameplayStopped). A dead player on a team is
-- back after HALT_RESPAWN seconds, as no respawn wave comes.
local HALT_RESPAWN = 3
local HALT_DOORS_INTERVAL = 2

local function Overlap(aMins, aMaxs, bMins, bMaxs)
	return aMins.x <= bMaxs.x and bMins.x <= aMaxs.x and aMins.y <= bMaxs.y and bMins.y <= aMaxs.y
		and aMins.z <= bMaxs.z and bMins.z <= aMaxs.z
end

-- The spawn doors: func_doors overlapped by a trigger_multiple whose
-- filter is a filter_activator_tfteam, and those triggers.
local function SpawnDoors()
	local triggers = {}
	for _, trigger in ipairs(ents.FindByClass("trigger_multiple")) do
		local filter = trigger:GetInternalVariable("m_hFilter")
		if IsValid(filter) and filter:GetClass() == "filter_activator_tfteam" then
			local mins, maxs = trigger:WorldSpaceAABB()
			triggers[#triggers + 1] = { ent = trigger, mins = mins, maxs = maxs }
		end
	end
	local doors, doorTriggers = {}, {}
	for _, door in ipairs(ents.FindByClass("func_door*")) do
		local mins, maxs = door:WorldSpaceAABB()
		local found = false
		for _, trigger in ipairs(triggers) do
			if Overlap(mins, maxs, trigger.mins, trigger.maxs) then
				found = true
				doorTriggers[trigger.ent] = true
			end
		end
		if found then doors[#doors + 1] = door end
	end
	return doors, doorTriggers
end

function ENT:Halted()
	return self.halted == true
end

function ENT:Halt()
	if self.state == S.GAME_OVER then
		-- out of the intermission: the frozen players are let go
		self.intermissionEnd = nil
		for _, ply in ipairs(player.GetAll()) do ply:Freeze(false) end
	end
	self.halted = true
	SetGlobal2Bool("tf2.halted", true)
	if self.state ~= S.BETWEEN_RNDS then self:StateTransition(S.BETWEEN_RNDS) end
	for _, t in ipairs(ents.FindByClass("team_round_timer")) do
		if t:InSetup() then t:FinishSetup() end
		t:Pause()
	end
	WETSAND.SetSetup(false)
	-- the doors stand open: their triggers, which would shut them as players
	-- leave, are off until the next game's map reset restores them
	local triggers
	self.spawnDoors, triggers = SpawnDoors()
	for trigger in pairs(triggers) do trigger:Fire("Disable") end
	for _, door in ipairs(self.spawnDoors) do
		door:Fire("Unlock")
		door:Fire("Open")
	end
	self.nextDoorsOpen = CurTime() + HALT_DOORS_INTERVAL
end

function ENT:StateEnter_BETWEEN_RNDS()
	self:TriggerOutput("OnStateEnterBetweenRounds", self)
	for _, logic in ipairs(ents.FindByClass("tf_logic_competitive")) do logic:SpawnRoomDoorsShouldUnlock() end
end

function ENT:Unhalt()
	self.halted = false
	self.spawnDoors = nil
	SetGlobal2Bool("tf2.halted", false)
end

function ENT:HaltedThink()
	local now = CurTime()
	if now >= (self.nextDoorsOpen or 0) then
		self.nextDoorsOpen = now + HALT_DOORS_INTERVAL
		for _, door in ipairs(self.spawnDoors or {}) do
			if IsValid(door) then door:Fire("Open") end
		end
	end
	for _, ply in ipairs(player.GetAll()) do
		if not ply:Alive() and WETSAND.TeamOf(ply) ~= WETSAND.TEAM_UNASSIGNED and ply:Team() ~= WETSAND.TEAM_SPECTATOR then
			ply.tf2HaltedDeath = ply.tf2HaltedDeath or now
			if now - ply.tf2HaltedDeath >= HALT_RESPAWN then
				ply.tf2HaltedDeath = nil
				ply:Spawn()
			end
		else
			ply.tf2HaltedDeath = nil
		end
	end
end

function ENT:Think()
	if self.halted then
		self:HaltedThink()
		self:NextThink(CurTime() + 0.1)
		return true
	end
	local think = self["StateThink_" .. StateName(self.state)]
	if think then think(self) end
	if self.state ~= S.GAME_OVER and CurTime() > self.nextPeriodic then
		self:PeriodicThink()
		self.nextPeriodic = CurTime() + 1
	end
	self:NextThink(CurTime() + 0.1)
	return true
end

-- CTeamplayRoundBasedRules::Think's once-a-second checks.
function ENT:PeriodicThink()
	if self.state ~= S.TEAM_WIN and self.state ~= S.STALEMATE then
		if self:CheckWinLimit() or self:CheckMaxRounds() then return end
	end
	self:CheckTeamCounts()
end

function ENT:TransitionDue()
	return self.transitionAt and CurTime() >= self.transitionAt
end

-- Players ------------------------------------------------------------------------------

function ENT:TeamPlayers(team)
	local players = {}
	for _, ply in ipairs(player.GetAll()) do
		if WETSAND.TeamOf(ply) == team then players[#players + 1] = ply end
	end
	return players
end

-- A player counts once their client has finished loading, so the pre-round
-- freeze is not spent on a loading screen. Bots have no client to report it.
local function Ready(ply)
	return ply.tf2Ready or ply:IsBot()
end

-- BHavePlayers: someone ready and on RED or BLU, or something else fighting
-- for a team (the AI war says so through TF2HaveCombatants).
function ENT:HavePlayers()
	for _, ply in ipairs(player.GetAll()) do
		if Ready(ply) and WETSAND.TeamOf(ply) ~= WETSAND.TEAM_UNASSIGNED then return true end
	end
	return hook.Run("TF2HaveCombatants") == true
end

-- RespawnPlayers(true): everyone but spectators, now.
function ENT:RespawnPlayers()
	for _, ply in ipairs(player.GetAll()) do
		if ply:Team() ~= WETSAND.TEAM_SPECTATOR then ply:Spawn() end
	end
end

-- Team1PlayersChanged / Team2PlayersChanged (CTFGameRulesProxy::TeamPlayerCountChanged).
function ENT:CheckTeamCounts()
	for team, output in pairs({ [RED] = "Team1PlayersChanged", [BLUE] = "Team2PlayersChanged" }) do
		local n = #self:TeamPlayers(team)
		if self.teamCounts[team] ~= n then
			self.teamCounts[team] = n
			self:TriggerOutput(output, self, tostring(n))
		end
	end
end

function ENT:Scores()
	return { [RED] = team.GetScore(RED), [BLUE] = team.GetScore(BLUE) }
end

-- PREGAME --------------------------------------------------------------------------------

-- Back to PREGAME with a full reset to come: the next pre-round cleans the
-- map up and respawns everyone, as a restart does. The AI war starts this
-- way. Out of the intermission, the frozen players are let go.
function ENT:RestartRound()
	if self.state == S.GAME_OVER then
		self.intermissionEnd = nil
		for _, ply in ipairs(player.GetAll()) do ply:Freeze(false) end
	end
	self.forceMapReset = true
	self.switchTeams = false
	self:StateTransition(S.PREGAME)
end

function ENT:StateThink_PREGAME()
	if self:HavePlayers() then self:StateTransition(S.PREROUND) end
end

-- PREROUND -------------------------------------------------------------------------------

function ENT:StateEnter_PREROUND()
	WETSAND.BalanceTeams(false)
	self:RoundRespawn()
	self.transitionAt = CurTime() + PREROUND_SECONDS * enableroundwaittime:GetFloat()
	SetGlobal2Float("tf2.preroundEnd", self.transitionAt)
	self:TriggerOutput("OnStateEnterPreRound", self)
end

function ENT:StateThink_PREROUND()
	if self:TransitionDue() then
		self:StateTransition(S.RND_RUNNING)
		return
	end
	self:CheckRespawnWaves()
end

function ENT:StateLeave_PREROUND()
	self:TriggerOutput("OnStateExitPreRound", self)
end

-- RND_RUNNING ----------------------------------------------------------------------------

-- State_Enter_RND_RUNNING and CTFGameRules::SetupOnRoundRunning. TF2's
-- PlayStartRoundVoice names Game.TeamRoundStart2/3, which no soundscript
-- defines, so it is silent there too.
function ENT:StateEnter_RND_RUNNING()
	self.nextWave = { [RED] = 0, [BLUE] = 0 }
	self:TriggerOutput("OnStateEnterRoundRunning", self)
	hook.Run("TF2RoundActive")
end

function ENT:StateThink_RND_RUNNING()
	if not self:HavePlayers() then
		self.forceMapReset = true
		self:StateTransition(S.PREGAME)
		return
	end
	self:CheckRespawnWaves()
	self:CheckTimelimitStalemate()
end

-- With SetStalemateOnTimelimit (or mp_match_end_at_timelimit) the time limit
-- ends the round: the higher score wins, a tie goes to sudden death.
function ENT:CheckTimelimitStalemate()
	if timelimit:GetInt() <= 0 or self:TimeLeft() > 0 then return end
	if not (self.allowStalemateAtTimelimit or matchEndAtTimelimit:GetBool()) then return end
	local winner = Lib().TimelimitWinner(self:Scores())
	if winner == WETSAND.TEAM_UNASSIGNED then
		self.changelevelAfterStalemate = true
		self:SetStalemate(Lib().STALEMATE.SERVER_TIMELIMIT, self.forceMapReset)
	else
		self:SetWinningTeam(winner, Lib().WINREASON.TIMELIMIT, true, false, true)
	end
end

-- TEAM_WIN (the humiliation: the losers cannot attack, see WETSAND.RestrictCommand) --------

function ENT:StateEnter_TEAM_WIN()
	if self.forceMapReset then self.roundsPlayed = self.roundsPlayed + 1 end
	self.transitionAt = CurTime() + math.max(5, bonusroundtime:GetInt())
	hook.Run("TF2RoundWin", self.winningTeam)
end

function ENT:StateThink_TEAM_WIN()
	if not self:TransitionDue() then return end
	if self:CheckTimeLimit() or self:CheckWinLimit() or self:CheckMaxRounds() then return end
	self:PreviousRoundEnd()
	self:StateTransition(S.PREROUND)
end

-- CTFGameRules::PreviousRoundEnd: the mini-round's OnEnd.
function ENT:PreviousRoundEnd()
	local master = WETSAND.Master()
	if IsValid(master) then master:FireRoundEndOutput() end
end

-- STALEMATE (sudden death) ----------------------------------------------------------------

-- State_Enter_STALEMATE and CTFGameRules::SetupOnStalemateStart: everyone
-- respawns once, the map's timer hides, and a stalemate timer of
-- mp_stalemate_timelimit seconds shows instead. Nobody respawns after that.
function ENT:StateEnter_STALEMATE()
	self.stalemateStart = CurTime()
	self:RespawnPlayers()
	self:HideActiveTimer()
	local seconds = stalemateTimelimit:GetInt()
	if seconds > 0 then self.stalemateTimer = self:CreateTimer(nil, seconds) end
end

function ENT:StateLeave_STALEMATE()
	if IsValid(self.stalemateTimer) then self.stalemateTimer:Remove() end
	self.stalemateTimer = nil
	self:RestoreActiveTimer()
end

function ENT:TeamLife()
	local teams = {}
	for team = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE do
		local players, alive = self:TeamPlayers(team), 0
		for _, ply in ipairs(players) do
			if ply:Alive() then alive = alive + 1 end
		end
		teams[team] = { players = #players, alive = alive }
	end
	return teams
end

function ENT:StateThink_STALEMATE()
	if not self:HavePlayers() then
		self.forceMapReset = true
		self:StateTransition(S.PREGAME)
		return
	end
	local winner, allDead = Lib().StalemateOutcome(self:TeamLife())
	if winner then
		-- Without a full reset the survivors take the round's points.
		local master = WETSAND.Master()
		if not self.forceMapReset and IsValid(master) then
			master:SetWinnerAndForceCaps(winner)
		else
			self:SetWinningTeam(winner, Lib().WINREASON.OPPONENTS_DEAD, self.forceMapReset)
		end
		return
	end
	local timerOut = IsValid(self.stalemateTimer) and WETSAND.TimerMayExpire() and self.stalemateTimer:TimeRemaining() <= 0
	if allDead or timerOut then
		self:SetWinningTeam(WETSAND.TEAM_UNASSIGNED, Lib().WINREASON.STALEMATE, not WETSAND.PlayingMiniRounds(), false)
	end
end

function ENT:InStalemate()
	return self.state == S.STALEMATE
end

-- Timers the gamerules make (stalemate and time limit), shown in the HUD.
function ENT:CreateTimer(name, seconds)
	local t = ents.Create("team_round_timer")
	if name then t:SetName(name) end
	t:SetKeyValue("show_in_hud", "1")
	t:Spawn()
	t:DoInput("SetTime", seconds)
	t:DoInput("Resume")
	t:DoInput("Enable")
	return t
end

-- HideActiveTimer / RestoreActiveTimer
function ENT:HideActiveTimer()
	self.previousActiveTimer = nil
	for _, t in ipairs(ents.FindByClass("team_round_timer")) do
		if t.showInHud == 1 then
			self.previousActiveTimer = t
			t:DoInput("ShowInHUD", 0)
		end
	end
end

function ENT:RestoreActiveTimer()
	if IsValid(self.previousActiveTimer) then self.previousActiveTimer:DoInput("ShowInHUD", 1) end
	self.previousActiveTimer = nil
end

-- GAME_OVER --------------------------------------------------------------------------------

-- GoToIntermission: everyone freezes for mp_chattime, then the map restarts
-- (TF2 would change to the next map in the cycle).
function ENT:GoToIntermission(reason)
	SetGlobal2String("tf2.round.gameover", reason)
	for _, ply in ipairs(player.GetAll()) do ply:Freeze(true) end
	self.intermissionEnd = CurTime() + chattime:GetInt()
	self:StateEnter(S.GAME_OVER)
end

function ENT:StateThink_GAME_OVER()
	if self.intermissionEnd and CurTime() >= self.intermissionEnd then
		self.intermissionEnd = nil
		RunConsoleCommand("changelevel", game.GetMap())
	end
end

-- Limits -------------------------------------------------------------------------------------

function ENT:TimeLeft()
	return Lib().TimeLeft(self.mapResetTime, timelimit:GetInt(), CurTime())
end

function ENT:CheckWinLimit()
	if not Lib().WinLimitReached(winlimit:GetInt(), self:Scores()) then return false end
	self:GoToIntermission("Reached Win Limit")
	return true
end

function ENT:CheckMaxRounds()
	if not Lib().MaxRoundsReached(maxrounds:GetInt(), self.roundsPlayed) then return false end
	self:GoToIntermission("Reached Round Limit")
	return true
end

function ENT:CheckTimeLimit()
	local master = WETSAND.Master()
	local mini = IsValid(master) and master:PlayingMiniRounds()
	local canChange = Lib().CanChangeLevelForTimeLimit(self.forceMapReset, mini,
		mini and master.playAllRounds, mini and master:NumPlayable() or 0)
	local reached = Lib().TimeLimitReached({
		timelimit = timelimit:GetInt(),
		timeLeft = self:TimeLeft(),
		canChange = canChange,
		afterStalemate = self.changelevelAfterStalemate == true,
	})
	if not reached then return false end
	self:GoToIntermission("Reached Time Limit")
	return true
end

-- Round control ------------------------------------------------------------------------------

function ENT:InSetup()
	return WETSAND.InSetup()
end

function ENT:SetInSetup(inSetup)
	WETSAND.SetSetup(inSetup)
end

function ENT:SetOvertime(overtime)
	WETSAND.SetOvertime(overtime)
end

function ENT:PointsMayBeCaptured()
	return (self.state == S.RND_RUNNING or self.state == S.STALEMATE) and not WETSAND.InSetup()
end

function ENT:AddPlayedRound(name)
	self.previousRounds = Lib().AddPlayedRound(self.previousRounds, name)
end

-- MapHasActiveTimer: a map timer (not the time limit one) shown in the HUD.
function ENT:MapHasActiveTimer()
	for _, t in ipairs(ents.FindByClass("team_round_timer")) do
		if t.showInHud == 1 and t:GetName() ~= TIMELIMIT_TIMER_NAME then return true end
	end
	return false
end

-- CreateTimeLimitTimer: only when the time limit will end the round.
function ENT:CreateTimeLimitTimer()
	if not (self.allowStalemateAtTimelimit or matchEndAtTimelimit:GetBool()) then return end
	self:CreateTimer(TIMELIMIT_TIMER_NAME, self:TimeLeft())
end

-- CTeamplayRoundBasedRules::RoundRespawn (with CTFGameRules's). A full reset
-- cleans the map up; a mini-round keeps it as it is.
function ENT:RoundRespawn()
	self.roundStartTime = CurTime()
	SetGlobal2Int("tf2.winner", WETSAND.TEAM_UNASSIGNED)
	if self.forceMapReset then
		if not self.mapFresh then game.CleanUpMap(false, CLEANUP_KEEPS) end
		self.mapFresh = false
		self.previousRounds = {}
		WETSAND.ActivateTimers()
		if timelimit:GetInt() > 0 and self:TimeLeft() > 0 and not self:MapHasActiveTimer() then
			self:CreateTimeLimitTimer()
		end
	end
	for t = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE do
		if self.originalWaveTime[t] >= 0 then self.waveTime[t] = self.originalWaveTime[t] end
	end
	self:SetupOnRoundStart()
	if self.switchTeams then
		self:HandleSwitchTeams()
		self.switchTeams = false
	end
	self:RespawnPlayers()
end

-- CTFGameRules::SetupOnRoundStart: every entity hears RoundSpawn, then
-- RoundActivate; the master picks the mini-round on RoundActivate.
function ENT:SetupOnRoundStart()
	WETSAND.SetOvertime(false)
	for _, t in ipairs(ents.FindByClass("team_round_timer")) do t:RoundSpawn() end
	for _, m in ipairs(ents.FindByClass("team_control_point_master")) do m:RoundSpawn() end
	hook.Run("TF2RoundSpawn")
	for _, p in ipairs(ents.FindByClass("team_control_point")) do WETSAND.PointRoundActivate(p) end
	for _, m in ipairs(ents.FindByClass("team_control_point_master")) do m:RoundActivate() end
	hook.Run("TF2RoundActivate")
end

-- CTFGameRules::HandleSwitchTeams: the players and their scores.
function ENT:HandleSwitchTeams()
	WETSAND.SwitchTeams()
	WETSAND.SwapTeamScores()
end

-- CTeamplayRoundBasedRules::PlayWinSong: each side hears its own result.
-- (The teamless would hear Game.TeamWin2/3, which no soundscript defines.)
local function PlayWinSong(winner)
	if winner == WETSAND.TEAM_UNASSIGNED then
		WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, "Game.Stalemate")
		return
	end
	WETSAND.BroadcastSound(winner, "Game.YourTeamWon")
	WETSAND.BroadcastSound(WETSAND.EnemyOf(winner), "Game.YourTeamLost")
end

-- What the win panel shows (SendWinPanelInfo).
function ENT:PublishWin(team, reason, forceMapReset)
	local master = WETSAND.Master()
	local remaining = 0
	if team ~= WETSAND.TEAM_UNASSIGNED and IsValid(master) then remaining = master:RoundsRemaining(team) end
	SetGlobal2Int("tf2.winner", team)
	SetGlobal2Int("tf2.round.winreason", reason)
	SetGlobal2Bool("tf2.round.fullround", forceMapReset)
	SetGlobal2Int("tf2.round.remaining", remaining)
end

-- CTeamplayRoundBasedRules::SetWinningTeam
function ENT:SetWinningTeam(winner, reason, forceMapReset, switchTeams, dontAddScore)
	if self.state == S.TEAM_WIN or self.state == S.GAME_OVER then return end
	forceMapReset = forceMapReset ~= false
	self.forceMapReset = forceMapReset
	self.switchTeams = switchTeams == true
	self.winningTeam = winner
	self.winReason = reason
	local reward = Lib().ShouldRewardTeam(forceMapReset, timelimit:GetInt(), self:TimeLeft(), dontAddScore == true)
	if reward and winner ~= WETSAND.TEAM_UNASSIGNED and WETSAND.ScorePerRound() then
		team.AddScore(winner, 1)
	end
	self:PublishWin(winner, reason, forceMapReset)
	self:StateTransition(S.TEAM_WIN)
	PlayWinSong(winner)
	if winner == WETSAND.TEAM_RED then self:TriggerOutput("OnWonByTeam1", self) end
	if winner == WETSAND.TEAM_BLUE then self:TriggerOutput("OnWonByTeam2", self) end
end

-- CTeamplayRoundBasedRules::SetStalemate: sudden death when
-- mp_stalemate_enable is on, otherwise a drawn round.
function ENT:SetStalemate(reason, forceMapReset, switchTeams)
	if not stalemateEnable:GetBool() then
		self:SetWinningTeam(WETSAND.TEAM_UNASSIGNED, Lib().WINREASON.STALEMATE, forceMapReset, switchTeams)
		return
	end
	if self.state == S.STALEMATE then return end
	self.forceMapReset = forceMapReset ~= false
	self.winningTeam = WETSAND.TEAM_UNASSIGNED
	SetGlobal2Int("tf2.round.stalematereason", reason)
	WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, "Game.SuddenDeath")
	self:StateTransition(S.STALEMATE)
end

-- Respawn waves (CheckRespawnWaves / GetNextRespawnWave) ----------------------------

function ENT:GetRespawnTimeScalar(team)
	local n = #self:TeamPlayers(team)
	return math.Remap(math.Clamp(n, 1, OPTIMAL_TEAM_SIZE), 1, OPTIMAL_TEAM_SIZE, 0.25, 1.0)
end

-- The wave length a team is set to: an admin's, else the map's, else
-- mp_respawnwavetime.
function ENT:TeamRespawnWaveTime(team)
	return Lib().WaveTime(self.adminWaveTime[team], self.waveTime[team], respawnwavetime:GetFloat())
end

function ENT:GetRespawnWaveMaxLength(team, scaleWithNumPlayers)
	if self.state ~= S.RND_RUNNING then return 0 end
	local t = self:TeamRespawnWaveTime(team)
	if scaleWithNumPlayers and t > MIN_SCALED_WAVE then
		t = math.max(MIN_SCALED_WAVE, t * self:GetRespawnTimeScalar(team))
	end
	return t
end

function ENT:ShouldRespawnQuickly(ply)
	return WETSAND.InSetup()
end

function ENT:GetMinTimeWhenPlayerMaySpawn(ply)
	local delay = DEATH_ANIM_LENGTH
	if not self:ShouldRespawnQuickly(ply) then
		delay = delay + self:GetRespawnWaveMaxLength(WETSAND.TeamOf(ply), false)
	end
	return (ply.tf2DeathTime or 0) + delay
end

function ENT:GetNextRespawnWave(team, ply)
	local minTime = self:GetMinTimeWhenPlayerMaySpawn(ply)
	if self:ShouldRespawnQuickly(ply) then return minTime end
	local nextWave = self.nextWave[team]
	local waveLength = self:GetRespawnWaveMaxLength(team, true)
	if waveLength <= 0 then return math.max(nextWave, minTime) end
	while nextWave < minTime do
		nextWave = nextWave + waveLength
	end
	return nextWave
end

function ENT:OnPlayerDeath(ply)
	ply.tf2DeathTime = CurTime()
	-- Sudden death has no respawns, nor does a game an admin stopped them in.
	if self.state == S.STALEMATE or self.respawnsDisabled then
		ply:SetNW2Float("tf2.respawnAt", 0)
		return
	end
	ply:SetNW2Float("tf2.respawnAt", self:GetNextRespawnWave(WETSAND.TeamOf(ply), ply))
end

function ENT:RespawnTeam(team)
	if self.respawnsDisabled then return end
	local now = CurTime()
	for _, ply in ipairs(self:TeamPlayers(team)) do
		if not ply:Alive() and now >= self:GetMinTimeWhenPlayerMaySpawn(ply) then
			ply:Spawn()
		end
	end
end

function ENT:CheckRespawnWaves()
	local now = CurTime()
	for team = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE do
		if self.nextWave[team] == 0 or self.nextWave[team] <= now then
			self:RespawnTeam(team)
			local length = self:GetRespawnWaveMaxLength(team, true)
			self.nextWave[team] = length > 0 and now + length or 0
		end
	end
end

-- Admin overrides (the Game Rules editor) --------------------------------------------

-- seconds >= 0 overrides the team's wave length for the rest of the map;
-- nil gives the map's back.
function ENT:SetAdminRespawnWaveTime(team, seconds)
	self.adminWaveTime[team] = seconds or UNSET
end

function ENT:RespawnsDisabled()
	return self.respawnsDisabled
end

-- Stopping respawns leaves the dead dead until the next full round (every
-- player respawns then); allowing them again puts the dead back in the
-- waves.
function ENT:SetRespawnsDisabled(disabled)
	if self.respawnsDisabled == disabled then return end
	self.respawnsDisabled = disabled
	if disabled or self.state == S.STALEMATE then return end
	for _, ply in ipairs(player.GetAll()) do
		local team = WETSAND.TeamOf(ply)
		if team ~= WETSAND.TEAM_UNASSIGNED and not ply:Alive() then
			ply:SetNW2Float("tf2.respawnAt", self:GetNextRespawnWave(team, ply))
		end
	end
end

-- Inputs ---------------------------------------------------------------------------------

-- SetTeamRespawnWaveTime / AddTeamRespawnWaveTime: the first value a team
-- receives is what each full round starts from again.
function ENT:SetTeamRespawnWaveTime(team, value)
	value = math.max(0, value)
	if self.originalWaveTime[team] < 0 then self.originalWaveTime[team] = value end
	self.waveTime[team] = value
end

function ENT:AddTeamRespawnWaveTime(team, value)
	local current = self.waveTime[team]
	if current < 0 then current = respawnwavetime:GetFloat() end
	if self.originalWaveTime[team] < 0 then self.originalWaveTime[team] = current end
	self.waveTime[team] = math.max(0, current + value)
end

-- Goal strings and roles, published for the HUD.
local function GoalSetter(team)
	return function(self, value)
		self.goalString[team] = tostring(value or "")
		SetGlobal2String("tf2.round.goal" .. team, self.goalString[team])
	end
end

local function RoleSetter(team)
	return function(self, value)
		self.role[team] = tonumber(value) or ROLE_NONE
		SetGlobal2Int("tf2.round.role" .. team, self.role[team])
	end
end

local function Ignore() end

local INPUTS = {
	setredteamrespawnwavetime = function(self, v) self:SetTeamRespawnWaveTime(RED, tonumber(v) or 0) end,
	setblueteamrespawnwavetime = function(self, v) self:SetTeamRespawnWaveTime(BLUE, tonumber(v) or 0) end,
	addredteamrespawnwavetime = function(self, v) self:AddTeamRespawnWaveTime(RED, tonumber(v) or 0) end,
	addblueteamrespawnwavetime = function(self, v) self:AddTeamRespawnWaveTime(BLUE, tonumber(v) or 0) end,
	setredteamgoalstring = GoalSetter(RED),
	setblueteamgoalstring = GoalSetter(BLUE),
	setredteamrole = RoleSetter(RED),
	setblueteamrole = RoleSetter(BLUE),
	addredteamscore = function(self, v) team.AddScore(RED, tonumber(v) or 0) end,
	addblueteamscore = function(self, v) team.AddScore(BLUE, tonumber(v) or 0) end,
	setrequiredobservertarget = function(self, v) WETSAND.SetRequiredObserverTarget(tostring(v or "")) end,
	setstalemateontimelimit = function(self, v)
		self.allowStalemateAtTimelimit = tonumber(v) == 1 or tostring(v) == "true"
	end,
	-- PlayVO is heard by everyone (BroadcastSound to 255), the others by one team.
	playvo = function(self, v) WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, tostring(v)) end,
	playvored = function(self, v) WETSAND.BroadcastSound(WETSAND.TEAM_RED, tostring(v)) end,
	playvoblue = function(self, v) WETSAND.BroadcastSound(WETSAND.TEAM_BLUE, tostring(v)) end,
	setroundrespawnfreezeenabled = function(self, value)
		WETSAND.RestartFreeze:SetBool(tonumber(value) ~= 0 and tostring(value) ~= "false")
	end,
	-- Accepted so the map's I/O is honoured, with no effect in GMod: no
	-- holiday map events, KOTH clocks, CTF bonus, upgrades file or truce.
	handlemapevent = Ignore,
	setmapforcedtruceduringbossfight = Ignore,
	setctfcapturebonustime = Ignore,
	setcustomupgradesfile = Ignore,
	setredkothclockactive = Ignore,
	setbluekothclockactive = Ignore,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
