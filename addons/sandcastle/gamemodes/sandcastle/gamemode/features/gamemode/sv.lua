-- The gamemode feature's controller: owns the games.system.gamemode model,
-- the gamemode's Sandbox or Gameplay mode, and turns its answers into the
-- rounds, sounds, notices and the sv_gameplay_enabled setting. The Gameplay
-- Settings' Begin Game and Stop Game buttons, an admin setting
-- sv_gameplay_enabled in the console, and the AI war all make requests
-- (Request). Sandbox mode is the gamerules' Halt (no rounds, timers paused,
-- spawn doors and forcefields open); a map with rounds starts in the mode
-- the setting holds (StartAtLoad), Gameplay mode after a countdown while
-- the players load. The transition to Gameplay mode owns
-- every cue, whoever asked: the map's description in the chat, the
-- countdown (its end networked as ws_gamemode_transition_end for the
-- round timer to show as "Prepare"; the announcer speaking the last
-- numbers), and its stages: the halted map cleaned up, the matchmaking
-- start sting and the announcer's tournament-start line, then Begin: the
-- scores cleared, everyone kept on their team or assigned one, and the
-- rounds' first pre-round (a full reset) respawning and holding them until
-- the countdown ends with the Administrator's line, when the round runs.
-- A game whose round mode's players are not
-- there yet (PLAYERS_NEEDED, mp_waitingforplayers) waits in Sandbox mode,
-- checked each WAIT_TICK, and counts down once they come; the count is
-- networked as ws_gamemode_waiting_have and _need (need 0: no wait). Its
-- ready-up (features.gamemode.ready) can end the wait sooner, or in MvM
-- must: F4 (gm_showspare2, TF2's ready key) or player_ready_toggle
-- toggles the player's team's ready (ws_ready_team_<team>) or, in MvM, the
-- player's own (NW2 ws_ready); everyone is unready when the wait ends.
local Gamemode = system.gamemode
local Gameplay = WS.require("features.gamemode.gameplay")
local Ready = WS.require("features.gamemode.ready")
local Rounds = gameplay.rounds

-- Both made in ws/sh_gameplay.lua.
local ENABLED = GetConVar("sv_gameplay_enabled")
local SANDBOX_DISABLED = GetConVar("sv_gameplay_disable_sandbox")

local TRANSITION_TIMER = "ws_gamemode_transition"
-- ws_gamemode_transition_end outside a transition.
local NO_TRANSITION = 0
local TRANSITION_TICK = 0.1 -- seconds between feeding the model the time; it cues on whole seconds

local waitingForPlayers = CreateConVar("mp_waitingforplayers", "1", FCVAR_NOTIFY,
	"1: a game begins only once its mode's players are there (arena, MvM), waiting in Sandbox mode until then", 0, 1)
local WAIT_TIMER = "ws_gamemode_waiting"
local WAIT_TICK = 1 -- seconds between counting the players a waiting game needs
local GAME_TEAMS = { WS.TEAM_RED, WS.TEAM_BLUE }

-- Sandbox mode begins with one of GMod's save/load chimes (sound files).
-- The transition with the casual matchmaking start sting and the
-- announcer's tournament-start line, and Gameplay mode with the
-- Administrator's competitive-match lines (soundscapes). A game called off
-- is the client's to sound (ws/sh_gameplay.lua).
local SANDBOX_SOUNDS = {
	"garrysmod/save_load1.wav",
	"garrysmod/save_load2.wav",
	"garrysmod/save_load3.wav",
	"garrysmod/save_load4.wav",
}
local TRANSITION_MUSIC = "MatchMaking.RoundStartCasual"
local TRANSITION_VOICE = "Announcer.TournamentModeStart"
-- The competitive announcer's countdown, by seconds left: the transition
-- voices those it reaches (it lasts Gamemode.COUNTDOWN seconds), and
-- [0] as Gameplay mode begins.
local ADMIN_LINES = {
	[60] = "Announcer.CompGame1Begins60Seconds",
	[30] = "Announcer.CompGame1Begins30Seconds",
	[10] = "Announcer.CompGame1Begins10Seconds",
	[5] = "Announcer.CompGameBegins05Seconds",
	[4] = "Announcer.CompGameBegins04Seconds",
	[3] = "Announcer.CompGameBegins03Seconds",
	[2] = "Announcer.CompGameBegins02Seconds",
	[1] = "Announcer.CompGameBegins01Seconds",
	[0] = "Announcer.CompGameBeginsFight"
}

local Controller = {
	mode = Gamemode.New(WS.Active(), ENABLED:GetBool()),
	transitionSounds = {}, -- what the transition has played, to silence if it is called off
	teamReady = { [WS.TEAM_RED] = false, [WS.TEAM_BLUE] = false },
}

-- To the unassigned team: everyone, spectators too.
local function SoundscapeToAll(name)
	WS.BroadcastSoundscape(WS.TEAM_UNASSIGNED, name)
end

local function SoundFileToAll(path)
	WS.BroadcastSoundFile(WS.TEAM_UNASSIGNED, path)
end

local function Pick(list)
	return list[math.random(#list)]
end

-- A requester is a player, or nil for the server console.
local function Tell(requester, text)
	if IsValid(requester) then requester:ChatPrint(text) else print(text) end
end

-- A title and lines in every player's chat (the client colours the title;
-- ws/sh_gameplay.lua).
local function Chat(title, lines)
	WS.Events.Fire("game_gameplay_chat", {
		title = title,
		lines = lines,
	})
end

-- What the map plays, for features.gamemode.gameplay: on a map without an
-- objective, the round limits too.
local function MapInfo()
	local info = {
		map = game.GetMap(),
		trains = #ents.FindByClass("team_train_watcher"),
		race = #ents.FindByClass("tf_logic_multiple_escort") > 0,
		points = #ents.FindByClass("team_control_point"),
		rounds = #ents.FindByClass("team_control_point_round"),
		flags = #ents.FindByClass("item_teamflag"),
	}
	local rounds = WS.Active() and WS.Feature("rounds")
	if rounds and not rounds:Mode().OBJECTIVE then
		local limits = rounds:RoundLimits()
		info.fraglimit, info.cashlimit = limits.frags, limits.cash
	end
	return info
end

-- Each team's players and the NPCs on the map fighting for it (the AI
-- war's soldiers, WSTeamCombatants), and the players on neither (free):
-- outside team play nobody picks a team, so the players a game waits for
-- choose theirs once it begins.
local function TeamCounts()
	local counts = { free = 0 }
	for _, t in ipairs(GAME_TEAMS) do counts[t] = hook.Run("WSTeamCombatants", t) or 0 end
	for _, ply in ipairs(player.GetAll()) do
		local t = WS.TeamOf(ply)
		if counts[t] then counts[t] = counts[t] + 1 else counts.free = counts.free + 1 end
	end
	return counts
end

-- How many count toward the round mode's player requirement, and how many
-- it needs (0 with mp_waitingforplayers off, or no rounds loaded).
-- The round mode's player requirement (its PLAYERS_NEEDED).
local function Needed()
	return WS.Active() and WS.Feature("rounds"):Mode().PLAYERS_NEEDED or Rounds.Mode.PLAYERS_NEEDED
end

local function PlayersNeeded()
	if not waitingForPlayers:GetBool() then return 0, 0 end
	return Rounds.PlayersNeeded(Needed(), TeamCounts())
end

local function ReadyKind()
	return Ready.Kind(GetGlobal2Bool("ws_mvm", false))
end

-- The team MvM's players ready on: its player requirement's (its defenders).
local function Defenders()
	return Needed().team or WS.TEAM_RED
end

-- The human players on each game team (bots never ready), and how many of
-- the defenders are ready.
local function Humans()
	local humans, readyDefenders = { [WS.TEAM_RED] = 0, [WS.TEAM_BLUE] = 0 }, 0
	local defenders = Defenders()
	for _, ply in ipairs(player.GetHumans()) do
		local t = WS.TeamOf(ply)
		if humans[t] then humans[t] = humans[t] + 1 end
		if t == defenders and ply:GetNW2Bool("ws_ready", false) then readyDefenders = readyDefenders + 1 end
	end
	return humans, readyDefenders
end

-- What features.gamemode.ready's Met and Enabled read.
local function ReadyQuery()
	local have, need = PlayersNeeded()
	local humans, readyDefenders = Humans()
	return {
		kind = ReadyKind(),
		have = have,
		need = need,
		humans = humans,
		teamReady = Controller.teamReady,
		defenders = Defenders(),
		readyDefenders = readyDefenders,
	}
end

-- Whether a game may begin: the round mode's player requirement, as its
-- ready-up meets it.
local function PlayersReady()
	return Ready.Met(ReadyQuery())
end

-- sv_gameplay_enabled follows a settled mode; the transition and the wait
-- leave it. The transition's end and the wait's count go to the clients'
-- round timer.
function Controller:Publish()
	local setting = Gamemode.SETTING[self.mode:Mode()]
	if setting ~= nil and ENABLED:GetBool() ~= setting then ENABLED:SetBool(setting) end
	SetGlobal2Float("ws_gamemode_transition_end", self.mode:TransitionEnd() or NO_TRANSITION)
	local have, need = 0, 0
	if self.mode:Mode() == Gamemode.WAITING then 
		have, need = PlayersNeeded()
	end
	SetGlobal2Int("ws_gamemode_waiting_have", have)
	SetGlobal2Int("ws_gamemode_waiting_need", need)
	for t, ready in pairs(self.teamReady) do SetGlobal2Bool("ws_ready_team_" .. t, ready) end
end

-- Everyone unready: the wait has ended, or been called off.
function Controller:ClearReady()
	for t in pairs(self.teamReady) do self.teamReady[t] = false end
	for _, ply in ipairs(player.GetAll()) do ply:SetNW2Bool("ws_ready", false) end
end

-- A ready left behind: a team whose players have all gone, a player no
-- longer a defender.
function Controller:DropStaleReady()
	local humans = Humans()
	for t in pairs(self.teamReady) do
		if humans[t] == 0 then self.teamReady[t] = false end
	end
	local defenders = Defenders()
	for _, ply in ipairs(player.GetAll()) do
		if WS.TeamOf(ply) ~= defenders and ply:GetNW2Bool("ws_ready", false) then ply:SetNW2Bool("ws_ready", false) end
	end
end

local READY_WORDS = { [true] = "Ready", [false] = "Not Ready" }

-- ply toggles the ready-up: their team's, or in MvM their own, while the
-- game waits for players and the toggle does anything (Ready.Enabled);
-- TF2's chat line says who changed it. The wait ends at once if that was
-- the last.
function Controller:ToggleReady(ply)
	if self.mode:Mode() ~= Gamemode.WAITING then return end
	local q = ReadyQuery()
	local t = WS.TeamOf(ply)
	if not Ready.MayToggle(q.kind, t, q.defenders) or not Ready.Enabled(q) then return end
	if q.kind == Ready.PLAYER then
		ply:SetNW2Bool("ws_ready", not ply:GetNW2Bool("ws_ready", false))
	else
		self.teamReady[t] = not self.teamReady[t]
		PrintMessage(HUD_PRINTTALK, string.format("%s changed team state to %s", ply:Nick(), READY_WORDS[self.teamReady[t]]))
	end
	self:WaitTick()
end

-- The wait: the players counted each WAIT_TICK until they are there, then
-- the transition.
function Controller:OpenWait()
	timer.Create(WAIT_TIMER, WAIT_TICK, 0, function() self:WaitTick() end)
end

function Controller:WaitTick()
	self:DropStaleReady()
	local answer = self.mode:Players(PlayersReady(), CurTime())
	if answer.action == Gamemode.START_TRANSITION then
		timer.Remove(WAIT_TIMER)
		self:ClearReady()
		self:OpenTransition()
	end
	self:Publish()
end

-- A transition soundscape, remembered so Stop Game can silence it.
function Controller:TransitionSound(name)
	self.transitionSounds[#self.transitionSounds + 1] = name
	SoundscapeToAll(name)
end

-- The transition's opening cue: the map's description in the chat, with
-- the seconds left.
function Controller:Opening()
	local title, lines = Gameplay.Describe(MapInfo())
	local left = math.ceil(self.mode:TransitionEnd() - CurTime())
	lines[#lines + 1] = string.format("Gameplay mode begins in %d seconds.", left)
	Chat(title, lines)
end

-- The transition's clock, fed to the model each TRANSITION_TICK.
function Controller:OpenClock()
	self.transitionSounds = {}
	timer.Create(TRANSITION_TIMER, TRANSITION_TICK, 0, function() self:Tick() end)
end

-- The game is set to begin with its players, however it came to: a
-- request's transition, a wait that ended, or a load's countdown opening
-- (hurried as its expected players came in, or reaching its last stretch).
-- RoundPlayersReady runs first, once a transition: its listeners, then the
-- gamemode's own (late addons register what they bring before the AI
-- war's scenarios compile, ws/sh_aiwar.lua); then the opening cues.
function Controller:PlayersReady()
	hook.Run("RoundPlayersReady")
	self:Opening()
end

-- A request's transition: its clock and its opening cues at once.
function Controller:OpenTransition()
	self:OpenClock()
	self:PlayersReady()
end

-- Calls off the transition, silencing what it played; a pre-round it
-- began is halted with the rest of the rounds.
function Controller:CancelTransition()
	timer.Remove(TRANSITION_TIMER)
	WS.Rules:Halt()
	WS.Events.Fire("game_gameplay_transition_cancelled", { sounds = self.transitionSounds })
	self.transitionSounds = {}
end

local ACTIONS = {
	[Gamemode.STAY] = function() end,
	[Gamemode.START_TRANSITION] = function(self) self:OpenTransition() end,
	-- the load's: its opening comes once the players are in (CUE_OPENING)
	[Gamemode.START_LOAD_COUNTDOWN] = function(self) self:OpenClock() end,
	[Gamemode.CANCEL_TRANSITION] = function(self) self:CancelTransition() end,
	[Gamemode.ENTER_SANDBOX] = function() WS.Rules:Halt() end,
	[Gamemode.WAIT] = function(self) self:OpenWait() end,
	[Gamemode.STOP_WAITING] = function(self)
		timer.Remove(WAIT_TIMER)
		self:ClearReady()
	end,
}

-- story: the requester's own notice, { title, lines } for the chat and
-- announcement for everyone's screen (the AI war's).
local NOTICES = {
	[Gamemode.NOTICE_NONE] = function() end,
	[Gamemode.NOTICE_REQUEST_CHAT] = function(_, story) Chat(story.title, story.lines) end,
	[Gamemode.NOTICE_REQUEST_ANNOUNCEMENT] = function(_, story) WS.Announce(story.announcement) end,
	[Gamemode.NOTICE_CALLED_OFF] = function()
		WS.Events.Fire("game_gameplay_called_off", {})
	end,
	[Gamemode.NOTICE_SANDBOX] = function()
		SoundFileToAll(Pick(SANDBOX_SOUNDS))
		WS.Announce("Gameplay mode has ended. Sandbox mode until a new game begins.")
	end,
	[Gamemode.NOTICE_REFUSED] = function(requester, _, refusal) Tell(requester, "Gameplay: " .. refusal) end,
	[Gamemode.NOTICE_WAITING] = function()
		local _, need = PlayersNeeded()
		WS.Announce(string.format("Waiting for %d players.", need))
	end,
	[Gamemode.NOTICE_DENIED] = function(requester, _, refusal)
		Tell(requester, "Gameplay: " .. refusal)
		if IsValid(requester) then WS.PlaySoundTo(requester, requester, Gamemode.DENY_SOUND) end
	end,
}

-- want: Gamemode.SANDBOX or GAMEPLAY; source: a Gamemode.SOURCE_*;
-- requester: the player who asked, or nil for the server console; story as
-- NOTICES takes it. Returns true, or false and why not (the requester has
-- been told, when the model says so).
function Controller:Request(want, source, requester, story)
	local answer = self.mode:Request(want, source, CurTime(), SANDBOX_DISABLED:GetBool(), PlayersReady())
	-- a game begun on a map without rounds: they load, halted until it begins
	if answer.loadRounds then WS.Feature("rounds"):EnsureRules() end
	ACTIONS[answer.action](self)
	NOTICES[answer.notice](requester, story, answer.refusal)
	self:Publish()
	if answer.refusal then return false, answer.refusal end
	return true
end

-- sv_gameplay_enabled changed: an admin's request, unless it was our own
-- write. Publish puts a refused one back.
function Controller:SettingChanged(enabled, requester)
	local want = self.mode:SettingWants(enabled)
	if want then self:Request(want, Gamemode.SOURCE_CONSOLE, requester) end
end

local CUES = {
	[Gamemode.CUE_OPENING] = function(self) self:PlayersReady() end,
	[Gamemode.CUE_CLEANUP] = function() WS.Rules:CleanUp() end,
	[Gamemode.CUE_ANNOUNCE] = function(self)
		self:TransitionSound(TRANSITION_MUSIC)
		self:TransitionSound(TRANSITION_VOICE)
	end,
	[Gamemode.CUE_PREROUND] = function(self) self:Begin() end,
	[Gamemode.CUE_COUNT] = function(self, cue)
		if ADMIN_LINES[cue.left] then self:TransitionSound(ADMIN_LINES[cue.left]) end
	end,
	-- the pre-round ends as the countdown does: the round runs to "Fight!"
	[Gamemode.CUE_ADMIN_LINE] = function() SoundscapeToAll(ADMIN_LINES[0]) end,
	[Gamemode.CUE_BEGIN] = function(self)
		timer.Remove(TRANSITION_TIMER)
		self.transitionSounds = {}
	end,
}

-- A map's load countdown is cut short once the players expected from the
-- previous map are in (games.system.gamemode's Hurry; ws/sv_arrivals.lua).
function Controller:Tick()
	local now = CurTime()
	if WS.ExpectedPlayersIn() then self.mode:Hurry(now) end
	for _, cue in ipairs(self.mode:Advance(now)) do CUES[cue.kind](self, cue) end
	self:Publish()
end

-- The first pre-round: the scores cleared, everyone on a team (a player on
-- RED or BLU keeps it, the rest but spectators are assigned one), then the
-- rounds respawn and hold them until the countdown ends. The match starts
-- here (MatchStart, for addons), once the teams are set and before the
-- rounds begin, so its first round's hooks (RoundStateChanged, RoundStart:
-- features/rounds/sv_effects.lua) come after it.
function Controller:Begin()
	team.SetScore(WS.TEAM_RED, 0)
	team.SetScore(WS.TEAM_BLUE, 0)
	for _, ply in ipairs(player.GetAll()) do
		if WS.TeamOf(ply) == WS.TEAM_UNASSIGNED and ply:Team() ~= WS.TEAM_SPECTATOR then
			WS.SetPlayerTeam(ply, WS.AutoTeam(), true)
		end
	end
	hook.Run("MatchStart")
	WS.Rules:BeginGame(self.mode:TransitionEnd())
	hook.Run("WSGameBegin")
end

-- A map with rounds starts in the mode sv_gameplay_enabled holds: Sandbox
-- mode halts the rounds; Gameplay mode counts down while the players load
-- (games.system.gamemode's Load), or waits for the players its mode needs,
-- the rounds halted until it begins. Rounds loaded for a game counting
-- down (a map without them) stay halted until it begins.
function Controller:StartAtLoad()
	ACTIONS[self.mode:Load(CurTime(), PlayersReady()).action](self)
	if self.mode:Mode() ~= Gamemode.GAMEPLAY then WS.Rules:Halt() end
	self:Publish()
end

-- TF2's ready key, F4: GMod binds it to gm_showspare2. player_ready_toggle
-- for a key of the player's own (the panel names whichever is bound).
hook.Add("ShowSpare2", "ws_gamemode_ready", function(ply) Controller:ToggleReady(ply) end)
concommand.Add("player_ready_toggle", function(ply)
	if IsValid(ply) then Controller:ToggleReady(ply) end
end, nil, "Toggle your team's ready, or in MvM your own, while a game waits for players")

return Controller
