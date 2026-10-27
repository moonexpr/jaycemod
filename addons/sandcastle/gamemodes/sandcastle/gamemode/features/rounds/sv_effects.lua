-- Part of the rounds controller (sv.lua): sounds and notices, logic_auto, and the
-- effects of the round model carried out.
local Controller, Players, PublishLimits, PublishOvertime, TIMELIMIT_TIMER_NAME, RULES_CLASSES = ...
local Rounds = gameplay.rounds
local Text = WS.require("features.rounds.text")
local TeamPlayers, EachPlayer = Players.TeamPlayers, Players.EachPlayer
local SwitchTeams, ScrambleTeams = Players.SwitchTeams, Players.ScrambleTeams

local S = WS.STATE
local UNASSIGNED, SPECTATOR = WS.TEAM_UNASSIGNED, WS.TEAM_SPECTATOR
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE

local LOGIC_AUTO_CLASS = "logic_auto"
local COMPETITIVE_CLASS = "tf_logic_competitive"
-- A full reset keeps the gamerules, as TF2 does, and the admin editors.
local CLEANUP_KEEPS = { "edit_gamerules", "edit_roundtimer" }
for _, class in ipairs(RULES_CLASSES) do CLEANUP_KEEPS[#CLEANUP_KEEPS + 1] = class end

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
-- the rotation's next, else this map again. The rotation is the map cycle
-- (mapcyclefile), or with mp_maplist_enabled the maplist: every installed
-- map the gamemode's map filter (sandcastle.txt's "maps") matches, in name
-- order.
local nextlevel = GetConVar("nextlevel")
local MAPLIST = CreateConVar("mp_maplist_enabled", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
	"1: after a match the next map is the next installed one the gamemode's map filter matches (the maplist), "
		.. "not the map cycle's (mapcyclefile); nextlevel still comes first", 0, 1)

local function MapInstalled(map)
	return file.Exists("maps/" .. map .. ".bsp", "GAME")
end

-- The gamemode's map filter, as GMod read it from its .txt.
local function MapFilter()
	local active = engine.ActiveGamemode()
	for _, gamemode in ipairs(engine.GetGamemodes()) do
		if gamemode.name == active then return gamemode.maps or "" end
	end
	return ""
end

local function InstalledMaps()
	local maps = {}
	for i, name in ipairs(file.Find("maps/*.bsp", "GAME")) do maps[i] = name:sub(1, -5) end
	return maps
end

-- The maplist (Rounds.MapsMatching's), and the filter it was matched by.
function Controller:Maplist()
	local filter = MapFilter()
	return Rounds.MapsMatching(InstalledMaps(), filter), filter
end

-- How near the match is to its end, for the next-map vote (Rounds.MapVoteDue).
function Controller:MatchEndFacts(now)
	local facts = self.round:Limits(now)
	facts.scores = { team.GetScore(RED), team.GetScore(BLUE) }
	facts.over = self:State() == S.GAME_OVER
	return facts
end

-- The rotation's next map: the maplist's, or the map cycle's.
local function RotationNext()
	if MAPLIST:GetBool() then
		return Rounds.MaplistNext((Controller:Maplist()), game.GetMap())
	end
	return game.GetMapNext()
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
-- (spawns, the AI war), and a round was won (winner, its WINREASON). Each
-- has its name for addons too: RoundStart, then SetupStart if the round
-- runs in setup (its setup timer, armed in the pre-round, counts from now;
-- an arena round's own); BonusRoundStart (winner, WINREASON), the bonus
-- round being the winners' time to hunt the humiliated (TEAM_WIN,
-- mp_bonusroundtime); BonusRoundEnd as the round state leaves it, however
-- (the next round, the match's end, a halt).
local ROUND_ACTIVE = "WSRoundActive"
local ROUND_WIN = "WSRoundWin"
local ROUND_HOOKS = {
	[ROUND_ACTIVE] = function(self)
		hook.Run(ROUND_ACTIVE)
		hook.Run("RoundStart")
		if self.round:InSetup() then hook.Run("SetupStart") end
	end,
	[ROUND_WIN] = function(_, args)
		hook.Run(ROUND_WIN, args[1], args[2])
		hook.Run("BonusRoundStart", args[1], args[2])
	end,
}

local function FireCompetitive(output)
	for _, logic in ipairs(ents.FindByClass(COMPETITIVE_CLASS)) do logic:TriggerOutput(output, logic) end
end

-- The team's wave: its dead whose wait is over, through the spawn manager.
local function RespawnTeam(self, t, now)
	local due = {}
	for _, ply in ipairs(TeamPlayers(t)) do
		if not ply:Alive() and self.round:MayRespawn(t, WS.RespawnCountsFrom(ply, ply.wsDeathTime or 0), now, ply.wsSwitchedTeam == true) then
			due[#due + 1] = ply
		end
	end
	WS.Respawn(due)
end

-- The level the match's end changes to (Rounds.NextMap): the next-map
-- vote's pick (WS.VotedNextLevel, ws/sv_votes.lua) is nextlevel's, before
-- its queued command has run.
local function NextMap()
	return Rounds.NextMap(WS.VotedNextLevel or nextlevel:GetString(), RotationNext(), game.GetMap(), MapInstalled)
end

local BONUS_FREEZE_TIMER = "ws_rounds_bonus_freeze"

local EFFECTS = {
	state = function(self, e)
		SetGlobal2Int("ws_round_state", e.to)
		PublishLimits()
		self:RetellDead()
		if e.from == S.TEAM_WIN then hook.Run("BonusRoundEnd") end
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
	-- the pre-round's cleanup: the map, and each client's ragdolls and decals
	cleanup = function(self)
		self:CleanUpMap()
		WS.Events.Fire("game_round_gore_cleared", {})
	end,
	clear_gore = function()
		game.RemoveRagdolls()
		WS.Events.Fire("game_round_gore_cleared", {})
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
	-- the arena round's setup (the model sets its own setup), on the timer as SETUP
	arena_setup = function(_, e)
		SetGlobal2Bool("ws_round_in_setup", true)
		SetGlobal2Float("ws_arena_setup_end", e.ends)
	end,
	-- the arena round fought: the dead are told none respawn
	arena_setup_end = function(self)
		SetGlobal2Bool("ws_round_in_setup", false)
		SetGlobal2Float("ws_arena_setup_end", 0)
		self:RetellDead()
	end,
	activate_timers = function(self) self:ActivateTimers() end,
	-- CreateTimeLimitTimer: the one timer, made once and set to the time left
	time_limit_timer = function(self, e)
		if IsValid(self.timeLimitTimer) then
			self:TimerInput(self.timeLimitTimer, "settime", e.seconds)
		else
			self.timeLimitTimer = self:CreateTimer(TIMELIMIT_TIMER_NAME, e.seconds)
		end
	end,
	remove_time_limit_timer = function(self)
		if IsValid(self.timeLimitTimer) then self.timeLimitTimer:Remove() end
		self.timeLimitTimer = NULL
	end,
	switch_teams = function() SwitchTeams() end,
	-- mp_scrambleteams_auto: told with the win, done as the next round starts
	scramble_due = function()
		WS.BroadcastPA(UNASSIGNED, SCRAMBLE_LINE)
		WS.Announce(Text.SCRAMBLE_NOTE, UNASSIGNED, UNASSIGNED, ICON_SCRAMBLE)
	end,
	scramble_teams = function() ScrambleTeams() end,
	respawn_all = function()
		local due = {}
		EachPlayer(function(ply)
			if ply:Team() ~= SPECTATOR then due[#due + 1] = ply end
		end)
		WS.Respawn(due)
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
		local due = {}
		EachPlayer(function(ply)
			if not ply:Alive() and WS.TeamOf(ply) ~= UNASSIGNED then due[#due + 1] = ply end
		end)
		WS.Respawn(due)
	end,
	doors_lock = function() FireCompetitive("OnSpawnRoomDoorsShouldLock") end,
	doors_unlock = function() FireCompetitive("OnSpawnRoomDoorsShouldUnlock") end,
	hook = function(self, e) ROUND_HOOKS[e.name](self, e.args) end,
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
	-- a tied match's deathmatch: frags alone, to mp_round_fraglimit
	deathmatch = function()
		WS.BroadcastPA(UNASSIGNED, SUDDEN_DEATH)
		WS.Announce(Text.DeathmatchNote(GetConVar("mp_round_fraglimit"):GetInt()), UNASSIGNED, UNASSIGNED, ICON_SUDDEN_DEATH)
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
	-- the match ended, its winner decided (nobody, drawn): MatchEnded (winner,
	-- why), for addons
	intermission = function(self, e, now)
		SetGlobal2String("ws_game_over_reason", e.reason)
		SetGlobal2Int("ws_match_winner", e.winner)
		SetGlobal2Float("ws_game_over_end", e["until"])
		hook.Run("WSMatchWin", e.winner)
		hook.Run("MatchEnded", e.winner, e.reason)
		-- its winners hunt the humiliated losers to its music through the
		-- setup gates and every spawn door (MATCH_WIN_EXTRA), then everyone
		-- is frozen for mp_chattime; a match ended drawn (a stalemate) is
		-- bonus time for all to the stalemate music, frozen never
		self:FinishSetup(now)
		self:OpenSpawnDoors(now)
		if e.winner == UNASSIGNED then PlayWinSong(UNASSIGNED) else PlayMatchEnd(e.winner) end
	end,
	changelevel = function()
		-- a next-map vote still running is counted first (ws/sv_votes.lua)
		hook.Run("WSChangeLevel")
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
	-- a bonus round's opening: nobody moves or attacks until it ends
	-- (WS.RestrictCommand), the AI war's soldiers held still (WSFreeze)
	bonus_freeze = function(self, e, now)
		SetGlobal2Float("ws_bonus_freeze_end", e.ends)
		hook.Run("WSFreeze", true)
		timer.Create(BONUS_FREEZE_TIMER, e.ends - now, 1, function()
			if WS.State() ~= S.GAME_OVER then hook.Run("WSFreeze", false) end
		end)
	end,
	-- the deathmatch's map has no setup: its gates open as the round starts
	skip_setup = function(self, e, now) self:FinishSetup(now) end,
}

-- Every change of the round's state is told to addons last, as
-- RoundStateChanged(previous, next) (the states games.gameplay.rounds.state
-- names): once the whole batch it came in is applied, so everything the
-- change brought (its outputs, respawns, RoundStart, BonusRoundStart...)
-- has run. A batch of several changes tells each, in order.
function Controller:Apply(effects)
	local now = CurTime()
	for _, e in ipairs(effects) do EFFECTS[e.kind](self, e, now) end
	for _, e in ipairs(effects) do
		if e.kind == "state" then hook.Run("RoundStateChanged", e.from, e.to) end
	end
end
