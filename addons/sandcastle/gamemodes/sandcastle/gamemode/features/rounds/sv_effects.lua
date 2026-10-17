-- Part of the rounds controller (sv.lua): sounds and notices, logic_auto, and the
-- effects of the round model carried out.
local Controller, Players, PublishLimits, PublishOvertime, TIMELIMIT_TIMER_NAME, PROXY_CLASS = ...
local Rounds = WS.require("foundation.rounds")
local Text = WS.require("foundation.rounds.text")
local TeamPlayers, EachPlayer = Players.TeamPlayers, Players.EachPlayer
local SwitchTeams, ScrambleTeams = Players.SwitchTeams, Players.ScrambleTeams

local S = WS.STATE
local UNASSIGNED, SPECTATOR = WS.TEAM_UNASSIGNED, WS.TEAM_SPECTATOR
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE

local LOGIC_AUTO_CLASS = "logic_auto"
local COMPETITIVE_CLASS = "tf_logic_competitive"
-- A full reset keeps the gamerules, as TF2 does, and the admin editors.
local CLEANUP_KEEPS = { PROXY_CLASS, "edit_gamerules", "edit_roundtimer" }

local SUDDEN_DEATH = "Game.SuddenDeath"

local SPECTATOR_WIN_MUSIC = "MatchMaking.RoundEndStalemateMusic"
local STALEMATE_LINE = "Announcer.CompRoundStalemate" -- vo/compmode/cm_admin_stalemate.mp3
-- The notification cards' icons (TF2's, as the admin notices'):
-- no respawn clock for sudden death, a clock for the next map.
local ICON_SUDDEN_DEATH = "hud/ico_time_none"
local ICON_NEXT_MAP = "hud/ico_time_10"
local ICON_SCRAMBLE = "hud/ico_teamswitch"
local SCRAMBLE_LINE = "Announcer.AM_TeamScrambleRandom"

-- The match won (GoToIntermission; a tie goes to sudden death instead):
-- each side its music on CHAN_AUTO (the spectators the winner's colour of
-- it), and the announcer names the winner to everyone on CHAN_VOICE2.
local MATCH_WIN_MUSIC, MATCH_LOSE_MUSIC = "MatchMaking.MatchEndWinMusicCasual", "MatchMaking.MatchEndLoseMusicCasual"
local MATCH_SPECTATOR_MUSIC = {
	[RED] = "MatchMaking.MatchEndRedWinMusic",
	[BLUE] = "MatchMaking.MatchEndBlueWinMusic",
}
local MATCH_WIN_LINE = {
	[RED] = "Announcer.CompMatchWinRed",
	[BLUE] = "Announcer.CompMatchWinBlu",
}

local function PlayMatchEnd(winner)
	WS.BroadcastSound(winner, MATCH_WIN_MUSIC)
	WS.BroadcastSound(WS.EnemyOf(winner), MATCH_LOSE_MUSIC)
	WS.BroadcastSound(SPECTATOR, MATCH_SPECTATOR_MUSIC[winner])
	WS.BroadcastPA(UNASSIGNED, MATCH_WIN_LINE[winner])
end

-- The level after the match (Rounds.NextMap): the engine's nextlevel, else
-- the map cycle's next (mapcyclefile), else this map again.
local nextlevel = GetConVar("nextlevel")

local function MapInstalled(map)
	return file.Exists("maps/" .. map .. ".bsp", "GAME")
end

-- CTeamplayRoundBasedRules::PlayWinSong: each side hears its own result.
-- (The teamless would hear Game.TeamWin2/3, which no soundscript defines.)
local function PlayWinSong(winner)
	if winner == UNASSIGNED then
		-- a tie: the stalemate music, the announcer calling it over it
		WS.BroadcastPA(UNASSIGNED, "Game.Stalemate")
		WS.BroadcastPA(UNASSIGNED, STALEMATE_LINE)
		return
	end
	WS.BroadcastPA(winner, "Game.YourTeamWon")
	WS.BroadcastPA(WS.EnemyOf(winner), "Game.YourTeamLost")
	-- spectators, of neither team, hear who won over the stalemate music
	-- (CHAN_AUTO, under the announcer's CHAN_VOICE2)
	WS.BroadcastPA(SPECTATOR, winner == BLUE and "Announcer.CompRoundWinBlu" or "Announcer.CompRoundWinRed")
	WS.BroadcastSound(SPECTATOR, SPECTATOR_WIN_MUSIC)

end

-- Sounds and notices -------------------------------------------------------------

-- CTFGameRules::PlaySpecialCapSounds, as the mode says.
function Controller:CapSounds(capTeam, wouldWinGame, scorePerRound)
	local lines = self.round:Mode():CapSounds(capTeam, {
		wouldWinGame = wouldWinGame,
		scorePerRound = scorePerRound,
	})
	for _, line in ipairs(lines) do WS.BroadcastPA(line.team, line.sound) end
end

-- logic_auto (CLogicAuto::Think) ----------------------------------------------------

-- A cleanup recreates every logic_auto, which would fire OnMultiNewMap as at
-- map load: GMod's gamerules never report InRoundRestart. Its keyvalue is
-- emptied while the cleanup runs, and OnMultiNewRound fires instead.
hook.Add("EntityKeyValue", "ws_rounds_new_map", function(ent, key)
	if Controller.suppressNewMap and ent:GetClass() == LOGIC_AUTO_CLASS and string.lower(key) == "onmultinewmap" then
		return ""
	end
end)

local function FireNewRoundOutputs()
	for _, auto in ipairs(ents.FindByClass(LOGIC_AUTO_CLASS)) do
		WS.FireOutput(auto, "OnMultiNewRound", auto)
	end
end

function Controller:CleanUpMap()
	self.suppressNewMap = true
	game.CleanUpMap(false, CLEANUP_KEEPS)
	self.suppressNewMap = false
end

-- Effects ---------------------------------------------------------------------------

-- The model's round hooks, for other features: the round is running
-- (spawns, the AI war), and a round was won (winner, its WINREASON).
local ROUND_ACTIVE = "WSRoundActive"
local ROUND_WIN = "WSRoundWin"
local ROUND_HOOKS = {
	[ROUND_ACTIVE] = function() hook.Run(ROUND_ACTIVE) end,
	[ROUND_WIN] = function(args) hook.Run(ROUND_WIN, args[1], args[2]) end,
}

local function FireCompetitive(output)
	for _, logic in ipairs(ents.FindByClass(COMPETITIVE_CLASS)) do logic:TriggerOutput(output, logic) end
end

local function RespawnTeam(self, t, now)
	for _, ply in ipairs(TeamPlayers(t)) do
		if not ply:Alive() and self.round:MayRespawn(t, ply.wsDeathTime or 0, now, ply.wsSwitchedTeam == true) then
			ply:Spawn()
		end
	end
end

-- The level the match's end changes to (Rounds.NextMap).
local function NextMap()
	return Rounds.NextMap(nextlevel:GetString(), game.GetMapNext(), game.GetMap(), MapInstalled)
end

local EFFECTS = {
	state = function(self, e)
		SetGlobal2Int("ws_round_state", e.to)
		PublishLimits()
		if e.to == S.PREROUND then
			self:RestoreSpawnDoors()
			SetGlobal2Float("ws_preround_end_time", e.preroundEnd)
			SetGlobal2Int("ws_round_winner", UNASSIGNED)
		end
	end,
	output = function(self, e)
		if IsValid(self.proxy) then self.proxy:TriggerOutput(e.name, self.proxy, e.value) end
	end,
	balance_teams = function() WS.BalanceTeams(false) end,
	cleanup = function(self) self:CleanUpMap() end,
	clear_gore = function()
		game.RemoveRagdolls()
		WS.Events.Fire("round_gore_cleared", {})
	end,
	new_round_outputs = function() timer.Simple(0, FireNewRoundOutputs) end,
	round_spawn = function(self)
		-- CTFGameRules::SetupOnRoundStart forgets the koth clocks.
		self.teamClocks = {}
		-- the round limits count from zero, and an admin's round time starts again
		self.tally:Reset()
		self:PublishRoundLimits()
		self:StartRoundTimer()
		self:RunListeners(Rounds.PHASE_SPAWN)
		hook.Run("WSRoundSpawn")
	end,
	round_activate = function(self)
		self:RunListeners(Rounds.PHASE_ACTIVATE)
		hook.Run("WSRoundActivate")
	end,
	previous_round_end = function(self) self:RunListeners(Rounds.PHASE_ROUND_END) end,
	arena_round_start = function(self) self:RunListeners(Rounds.PHASE_ARENA_START) end,
	activate_timers = function(self) self:ActivateTimers() end,
	time_limit_timer = function(self, e) self:CreateTimer(TIMELIMIT_TIMER_NAME, e.seconds) end,
	switch_teams = function() SwitchTeams() end,
	-- mp_scrambleteams_auto: told with the win, done as the next round starts
	scramble_due = function()
		WS.BroadcastPA(UNASSIGNED, SCRAMBLE_LINE)
		WS.Announce(Text.SCRAMBLE_NOTE, UNASSIGNED, UNASSIGNED, ICON_SCRAMBLE)
	end,
	scramble_teams = function() ScrambleTeams() end,
	respawn_all = function()
		EachPlayer(function(ply)
			if ply:Team() ~= SPECTATOR then ply:Spawn() end
		end)
	end,
	respawn_team = function(self, e, now) RespawnTeam(self, e.team, now) end,
	-- Sudden death over: its survivors, players and the AI war's soldiers
	-- (WSSuddenDeathOver), overhealed (Rounds.SurvivorHealth), then
	-- every dead player on a team back, to enjoy the victory or the
	-- humiliation.
	sudden_death_over = function()
		EachPlayer(function(ply)
			if ply:Alive() and WS.TeamOf(ply) ~= UNASSIGNED then
				ply:SetHealth(Rounds.SurvivorHealth(ply:GetMaxHealth(), ply:Health()))
			end
		end)
		hook.Run("WSSuddenDeathOver", Rounds.SurvivorHealth)
		EachPlayer(function(ply)
			if not ply:Alive() and WS.TeamOf(ply) ~= UNASSIGNED then ply:Spawn() end
		end)
	end,
	doors_lock = function() FireCompetitive("OnSpawnRoomDoorsShouldLock") end,
	doors_unlock = function() FireCompetitive("OnSpawnRoomDoorsShouldUnlock") end,
	hook = function(self, e) ROUND_HOOKS[e.name](e.args) end,
	score = function(self, e) team.AddScore(e.team, e.points) end,
	-- What the win panel shows (SendWinPanelInfo).
	publish_win = function(self, e, now)
		local remaining = 0
		if e.winner ~= UNASSIGNED then remaining = self.objective:RoundsRemaining(e.winner) end
		SetGlobal2Int("ws_round_winner", e.winner)
		SetGlobal2Int("ws_round_win_reason", e.reason)
		SetGlobal2Bool("ws_round_full_round", e.fullRound)
		SetGlobal2Int("ws_rounds_remaining", remaining)
		-- a team's win opens the setup gates and every spawn door, so its
		-- side can hunt the humiliated losers down
		if e.winner ~= UNASSIGNED then
			self:FinishSetup(now)
			self:OpenSpawnDoors(now)
		end
	end,
	win_song = function(self, e)
		PlayWinSong(e.winner)
		for t, line in pairs(self.round:Mode():RoundWinLines(e.winner, e.fullRound, self.multipleTrains)) do
			WS.BroadcastPA(t, line)
		end
	end,
	-- nobody respawns, so the setup gates (the map's OnSetupFinished relays)
	-- and every spawn door open: the last of each side have nowhere to hide
	sudden_death = function(self, e, now)
		WS.BroadcastPA(UNASSIGNED, SUDDEN_DEATH)
		WS.Announce(Text.SuddenDeathNote(e.reason), UNASSIGNED, UNASSIGNED, ICON_SUDDEN_DEATH)
		self:FinishSetup(now)
		self:OpenSpawnDoors(now)
	end,
	hide_timers = function(self) self:HideActiveTimer() end,
	restore_timers = function(self) self:RestoreActiveTimer() end,
	-- sudden death after the arena round, or after another, replaces its timer
	stalemate_timer = function(self, e)
		if IsValid(self.stalemateTimer) then self.stalemateTimer:Remove() end
		self.stalemateTimer = self:CreateTimer(nil, e.seconds)
	end,
	-- Without a full reset the survivors take the round's points (the
	-- master's SetWinnerAndForceCaps).
	stalemate_winner = function(self, e)
		if not e.forceMapReset and self.objective.SuddenDeathWin then
			self.objective:SuddenDeathWin(e.team)
		else
			self:SetWinningTeam(e.team, Rounds.WINREASON.OPPONENTS_DEAD, e.forceMapReset)
		end
	end,
	intermission = function(self, e, now)
		SetGlobal2String("ws_game_over_reason", e.reason)
		SetGlobal2Int("ws_match_winner", e.winner)
		SetGlobal2Float("ws_game_over_end", e["until"])
		hook.Run("WSMatchWin", e.winner)
		-- its winners hunt the humiliated losers to its music through the
		-- setup gates and every spawn door (MATCH_WIN_EXTRA), then everyone
		-- is frozen for mp_chattime; a match ended drawn (a stalemate) is
		-- bonus time for all to the stalemate music, frozen never
		self:FinishSetup(now)
		self:OpenSpawnDoors(now)
		if e.winner == UNASSIGNED then PlayWinSong(UNASSIGNED) else PlayMatchEnd(e.winner) end
	end,
	changelevel = function()
		RunConsoleCommand("changelevel", NextMap())
	end,
	-- mp_chattime at the match's end: everyone frozen, the AI war's soldiers
	-- too (WSFreeze), until the level changes
	freeze = function()
		EachPlayer(function(ply) ply:Freeze(true) end)
		hook.Run("WSFreeze", true)
		WS.Announce(Text.NextMapNote(NextMap()), UNASSIGNED, UNASSIGNED, ICON_NEXT_MAP)
	end,
	-- a match ended drawn: bonus time goes on, the next map named
	next_map = function()
		WS.Announce(Text.NextMapNote(NextMap()), UNASSIGNED, UNASSIGNED, ICON_NEXT_MAP)
	end,
	unfreeze = function()
		EachPlayer(function(ply) ply:Freeze(false) end)
		hook.Run("WSFreeze", false)
	end,
	overtime = function(self, e) PublishOvertime(e.value) end,
}

function Controller:Apply(effects)
	local now = CurTime()
	for _, e in ipairs(effects) do EFFECTS[e.kind](self, e, now) end
end
