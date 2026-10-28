-- Part of the rounds controller (sv.lua): the gamerules surface the gamerules
-- (tf_gamerules, ws_gamerules) forward, the spawn doors of a stopped game,
-- and their inputs, tf_gamerules'.
local Controller, Players, Active = ...
local Rounds = gameplay.rounds
local Spawns = system.spawn_manager
local SpawnHold = WS.require("features.rounds.spawn_doors")
local TeamPlayers, EachPlayer = Players.TeamPlayers, Players.EachPlayer

local UNASSIGNED, SPECTATOR = WS.TEAM_UNASSIGNED, WS.TEAM_SPECTATOR
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE

local HALT_DOORS_INTERVAL = 2
local ROLE_NONE = 0 -- TEAM_ROLE_NONE

-- The spawn doors of a stopped game ---------------------------------------------------

local Overlap = math.box.Overlaps

-- func_doors overlapped by a trigger_multiple whose filter is a
-- filter_activator_tfteam, and those triggers.
local function SpawnDoors()
	local triggers = {}
	for _, trigger in ipairs(ents.FindByClass("trigger_multiple")) do
		local filter = trigger:GetInternalVariable("m_hFilter")
		if IsValid(filter) and filter:GetClass() == "filter_activator_tfteam" then
			local mins, maxs = trigger:WorldSpaceAABB()
			triggers[#triggers + 1] = {
				ent = trigger,
				mins = mins,
				maxs = maxs,
			}
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

-- The gamerules surface the gamerules forward ------------------------------------------

-- Without rounds there are no respawn waves: the player clicks to respawn,
-- as in Sandbox.
function Controller:OnPlayerDeath(ply)
	if not Active() then return end
	local now = CurTime()
	ply.wsDeathTime = now
	-- a death that changed the player's team (WS.SetPlayerTeam) waits only
	-- for the new team's next wave
	ply.wsSwitchedTeam = ply.wsChangingTeam == true
	local t = WS.TeamOf(ply)
	-- Sandbox mode: no waves, the player clicks to respawn (GM:PlayerDeathThink)
	if t == UNASSIGNED or WS.GameplayStopped() then return WS.SetSpawnStatus(ply, Spawns.NONE, 0) end
	-- what the player did moves their wait, at most a wave sooner (ws/sv_respawn_modifiers.lua)
	local countsFrom = now + WS.RespawnAdjust(ply, now, self.round:WaveMaxLength(t, 0, false))
	WS.SetSpawnStatus(ply, self.round:RespawnStatus(t, countsFrom, #TeamPlayers(t), ply.wsSwitchedTeam))
end

-- mp_round_restart, the reset vote and the editors: a round
-- with players on RED or BLU (not NPCs alone) ends as a stalemate, with the
-- round end's own panel and song; with none it restarts silently
-- (games.gameplay.rounds' RestartRound).
function Controller:RestartRound()
	local withPlayers = #TeamPlayers(RED) + #TeamPlayers(BLUE) > 0
	self:Apply(self.round:RestartRound(CurTime(), withPlayers))
end

-- A passed scramble vote: the next round's teams are scrambled.
function Controller:ScheduleScramble()
	self:Apply(self.round:ScheduleScramble())
end

function Controller:ScramblePending()
	return self.round:ScramblePending()
end

-- An admin's sudden death for the running round; forMatch: its winner wins
-- the match. True, or false and why.
function Controller:SuddenDeathNow(forMatch)
	if not self.round:Underway() then return false, "no round is running" end
	local now = CurTime()
	self:Apply(forMatch and self.round:SuddenDeathForMatch(now) or self.round:SuddenDeath(now, Rounds.STALEMATE.ADMIN))
	return true
end

-- An admin ends the match now, won by team. True, or false and why.
function Controller:ForceMatchWin(team)
	local effects = self.round:ForceMatchWin(CurTime(), team)
	if #effects == 0 then return false, "the match is already over" end
	self:Apply(effects)
	return true
end

function Controller:Halted()
	return self.round:Halted()
end

-- Stopping the game (non-gameplay mode): the round waits between rounds and
-- every timer pauses. Setup, if it is on, ends as its clock running out
-- would, so the map opens its own setup gates. The spawn doors stand open:
-- their triggers, which would shut them as players leave, are off until the
-- next game's map reset restores them.
function Controller:Halt()
	local now = CurTime()
	self:Apply(self.round:Halt(now))
	SetGlobal2Bool("ws_gameplay_halted", true)
	self:FinishSetup(now)
	for _, ent in ipairs(self.timerList) do
		if IsValid(ent) then self.timers[ent]:Pause(now) end
	end
	self:OpenSpawnDoors(now)
	self:PublishHudTimer(now)
end

-- Setup, if it is on, ends as its clock running out would (OnSetupFinished),
-- so the map opens its own setup gates.
function Controller:FinishSetup(now)
	for _, ent in ipairs(self.timerList) do
		local timer = self.timers[ent]
		if IsValid(ent) and timer:InSetup() then self:ApplyTimerEvents(ent, timer:FinishSetup(now)) end
	end
	self:SetSetup(false)
end

-- Every spawn door unlocked and open, its triggers off so none shuts it
-- (KeepSpawnDoorsOpen holds them open), until RestoreSpawnDoors or the next
-- map reset. The triggers that were on are remembered, with what the map
-- does to them meanwhile.
function Controller:OpenSpawnDoors(now)
	if not self.spawnDoors then
		local doors, triggers = SpawnDoors()
		local on = {}
		for trigger in pairs(triggers) do
			if not trigger:GetInternalVariable("m_bDisabled") then on[#on + 1] = trigger end
		end
		self.spawnDoors, self.spawnTriggers, self.spawnHold = doors, triggers, SpawnHold.New(on)
		self.switchingTriggers = true
		for _, trigger in ipairs(on) do trigger:Input("Disable") end
		self.switchingTriggers = false
	end
	for _, door in ipairs(self.spawnDoors) do
		if IsValid(door) then
			door:Fire("Unlock")
			door:Fire("Open")
		end
	end
	self.nextDoorsOpen = now + HALT_DOORS_INTERVAL
end

-- The next round (a stage of a multi-stage map has no map reset): the
-- triggers that were on, on again unless the map has since turned them off,
-- with those it turned on, and the doors closed for them to open.
function Controller:RestoreSpawnDoors()
	if self.spawnHold then
		self.switchingTriggers = true
		for _, trigger in ipairs(self.spawnHold:ToEnable()) do
			if IsValid(trigger) then trigger:Input("Enable") end
		end
		self.switchingTriggers = false
	end
	for _, door in ipairs(self.spawnDoors or {}) do
		if IsValid(door) then door:Fire("Close") end
	end
	self.spawnDoors, self.spawnTriggers, self.spawnHold = nil, nil, nil
end

-- The map's own Enable and Disable of a held trigger: a stage's handover in
-- the bonus time (pl_goldrush's cap_a_capture_relay) outlasts the hold.
hook.Add("AcceptInput", "ws_rounds_spawn_doors", function(ent, input)
	local self = Controller
	if self.switchingTriggers or not (self.spawnTriggers and self.spawnTriggers[ent]) then return end
	self.spawnHold:MapInput(ent, string.lower(input))
end)

function Controller:KeepSpawnDoorsOpen(now)
	if now < self.nextDoorsOpen then return end
	self.nextDoorsOpen = now + HALT_DOORS_INTERVAL
	for _, door in ipairs(self.spawnDoors or {}) do
		if IsValid(door) then door:Fire("Open") end
	end
end

-- A new game readies in two steps (games.gameplay.rounds' CleanUp and
-- BeginGame): the halted map cleaned up, then the first pre-round, held
-- until preroundEnd.
function Controller:CleanUp()
	self:Apply(self.round:CleanUp())
end

function Controller:BeginGame(preroundEnd)
	SetGlobal2Bool("ws_gameplay_halted", false)
	local now = CurTime()
	self:Apply(self.round:BeginGame(now, preroundEnd, self:World(now)))
end

-- A stopped game: the doors stay open, and a dead player on a team is back
-- after a pause, as no respawn wave comes.
function Controller:HaltedThink(now)
	self:KeepSpawnDoorsOpen(now)
	EachPlayer(function(ply)
		if not ply:Alive() and WS.TeamOf(ply) ~= UNASSIGNED and ply:Team() ~= SPECTATOR then
			ply.wsHaltedDeath = ply.wsHaltedDeath or now
			if Rounds.HaltedRespawnDue(ply.wsHaltedDeath, now) then
				ply.wsHaltedDeath = nil
				WS.Respawn({ ply })
			end
		else
			ply.wsHaltedDeath = nil
		end
	end)
end

function Controller:RespawnsDisabled()
	return self.round:RespawnsDisabled()
end

-- Allowing respawns again puts the dead back in the waves.
function Controller:SetRespawnsDisabled(disabled)
	if not self.round:SetRespawnsDisabled(disabled) then return end
	self:RetellDead()
end

-- A helped team's share of its respawn wave (Help Other Team,
-- ws/sv_handicap.lua); the dead hear their new wait.
function Controller:SetWaveScale(t, scale)
	self.round:SetWaveScale(t, scale)
	self:RetellDead()
end

-- Every dead player's respawn status again, as the round now has it: a
-- wave's countdown, or none to come (sudden death, the arena round).
function Controller:RetellDead()
	EachPlayer(function(ply)
		if not ply:Alive() and WS.TeamOf(ply) ~= UNASSIGNED then self:OnPlayerDeathTime(ply) end
	end)
end

-- A dead player's respawn time again, from their death.
function Controller:OnPlayerDeathTime(ply)
	local t = WS.TeamOf(ply)
	if WS.GameplayStopped() then return WS.SetSpawnStatus(ply, Spawns.NONE, 0) end
	WS.SetSpawnStatus(ply, self.round:RespawnStatus(t, WS.RespawnCountsFrom(ply, ply.wsDeathTime or CurTime()), #TeamPlayers(t),
		ply.wsSwitchedTeam == true))
end

-- The Game Rules editor's override: seconds >= 0, or nil for the map's.
function Controller:SetAdminRespawnWaveTime(t, seconds)
	self.round:SetAdminWaveTime(t, seconds)
end

function Controller:TeamRespawnWaveTime(t)
	return self.round:TeamWaveTime(t)
end

function Controller:GetRespawnWaveMaxLength(t, scaleWithNumPlayers)
	return self.round:WaveMaxLength(t, #TeamPlayers(t), scaleWithNumPlayers)
end

-- tf_gamerules' inputs (CTFGameRulesProxy) -------------------------------------------

local function WaveSetter(t)
	return function(self, v) self.round:SetTeamWaveTime(t, tonumber(v) or 0) end
end

local function WaveAdder(t)
	return function(self, v) self.round:AddTeamWaveTime(t, tonumber(v) or 0) end
end

-- Goal strings and roles, published for the HUD.
local function GoalSetter(t)
	return function(self, v) SetGlobal2String("ws_round_goal_" .. t, tostring(v or "")) end
end

local function RoleSetter(t)
	return function(self, v) SetGlobal2Int("ws_round_role_" .. t, tonumber(v) or ROLE_NONE) end
end

local function ScoreAdder(t)
	return function(self, v) team.AddScore(t, tonumber(v) or 0) end
end

local function VoiceTo(t)
	return function(self, v) WS.BroadcastSoundscape(t, tostring(v)) end
end

local function ClockActivator(t)
	return function(self) self:ActivateTeamClock(t) end
end

local function Ignore() end

local PROXY_INPUTS = {
	setredteamrespawnwavetime = WaveSetter(RED),
	setblueteamrespawnwavetime = WaveSetter(BLUE),
	addredteamrespawnwavetime = WaveAdder(RED),
	addblueteamrespawnwavetime = WaveAdder(BLUE),
	setredteamgoalstring = GoalSetter(RED),
	setblueteamgoalstring = GoalSetter(BLUE),
	setredteamrole = RoleSetter(RED),
	setblueteamrole = RoleSetter(BLUE),
	addredteamscore = ScoreAdder(RED),
	addblueteamscore = ScoreAdder(BLUE),
	setrequiredobservertarget = function(self, v) WS.SetRequiredObserverTarget(tostring(v or "")) end,
	setstalemateontimelimit = function(self, v)
		self.round:SetStalemateOnTimelimit(tonumber(v) == 1 or tostring(v) == "true")
	end,
	-- PlayVO is heard by everyone (BroadcastSoundscape to 255), the others by one team.
	playvo = VoiceTo(UNASSIGNED),
	playvored = VoiceTo(RED),
	playvoblue = VoiceTo(BLUE),
	setroundrespawnfreezeenabled = function(self, v)
		WS.RestartFreeze:SetBool(tonumber(v) ~= 0 and tostring(v) ~= "false")
	end,
	setredkothclockactive = ClockActivator(RED),
	setbluekothclockactive = ClockActivator(BLUE),
	-- Accepted so the map's I/O is honoured, with no effect in GMod: no
	-- holiday map events, CTF bonus, upgrades file or truce.
	handlemapevent = Ignore,
	setmapforcedtruceduringbossfight = Ignore,
	setctfcapturebonustime = Ignore,
	setcustomupgradesfile = Ignore,
}

-- A tf_gamerules input, in any case; returns whether it is one.
function Controller:ProxyInput(name, value)
	local handler = PROXY_INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
