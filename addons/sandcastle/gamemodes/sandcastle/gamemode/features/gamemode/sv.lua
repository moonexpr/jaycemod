-- The gamemode feature's controller: owns the foundation.gamemode model,
-- the gamemode's Sandbox or Gameplay mode, and turns its answers into the
-- rounds, sounds, notices and the sv_gameplay_enabled setting. The Gameplay
-- Settings' Begin Game and Stop Game buttons, an admin setting
-- sv_gameplay_enabled in the console, and the AI war all make requests
-- (Request). Sandbox mode is the gamerules' Halt (no rounds, timers paused,
-- spawn doors and forcefields open); a map with rounds starts in the mode
-- the setting holds (StartAtLoad), Gameplay mode after a countdown while
-- the players load. The transition to Gameplay mode owns
-- every cue, whoever asked: the map's description in the chat, the
-- matchmaking start sting and the announcer's tournament-start line, the
-- countdown (its end networked as ws_gamemode_transition_end for the
-- round timer to show as "Prepare"; the announcer speaking the last
-- numbers) and the Administrator's line; then Begin: the scores cleared,
-- the round system restarted from scratch (RestartRound's full reset, as a map's first round)
-- and everyone unassigned, as on joining, so each client opens its team
-- menu until they choose a team. A game whose round mode's players are not
-- there yet (PLAYERS_NEEDED, mp_waitingforplayers) waits in Sandbox mode,
-- checked each WAIT_TICK, and counts down once they come; the count is
-- networked as ws_gamemode_waiting_have and _need (need 0: no wait).
local Gamemode = WS.require("foundation.gamemode")
local Gameplay = WS.require("features.gamemode.gameplay")
local Rounds = WS.require("foundation.rounds")

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

-- Sandbox mode begins with one of GMod's save/load chimes. The transition
-- with the casual matchmaking start sting and one of the announcer's
-- tournament-start lines, and Gameplay mode with one of the
-- Administrator's competitive-match lines.
local SANDBOX_SOUNDS = {
	"garrysmod/save_load1.wav",
	"garrysmod/save_load2.wav",
	"garrysmod/save_load3.wav",
	"garrysmod/save_load4.wav",
}
local TRANSITION_MUSIC = "MatchMaking.RoundStartCasual"
local TRANSITION_VOICES = {
	"vo/announcer_tournament_started1.mp3",
	"vo/announcer_tournament_started2.mp3",
	"vo/announcer_tournament_started3.mp3",
	"vo/announcer_tournament_started4.mp3",
}
local CALLED_OFF_SFX = "ui/vote_failure.wav"
-- The competitive announcer's countdown, by seconds left: the transition
-- voices those it reaches (it lasts Gamemode.ADMIN_LINE_AT seconds), and
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
}

local function PlayToAll(path)
	WS.BroadcastPA(WS.TEAM_UNASSIGNED, path) -- the unassigned team: everyone, spectators too
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
local function PlayersNeeded()
	if not waitingForPlayers:GetBool() then return 0, 0 end
	local needed = WS.Active() and WS.Feature("rounds"):Mode().PLAYERS_NEEDED or Rounds.Mode.PLAYERS_NEEDED
	return Rounds.PlayersNeeded(needed, TeamCounts())
end

local function PlayersReady()
	local have, need = PlayersNeeded()
	return have >= need
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
end

-- The wait: the players counted each WAIT_TICK until they are there, then
-- the transition.
function Controller:OpenWait()
	timer.Create(WAIT_TIMER, WAIT_TICK, 0, function() self:WaitTick() end)
end

function Controller:WaitTick()
	local answer = self.mode:Players(PlayersReady(), CurTime())
	if answer.action == Gamemode.START_TRANSITION then
		timer.Remove(WAIT_TIMER)
		self:OpenTransition()
	end
	self:Publish()
end

-- A transition sound, remembered so Stop Game can silence it.
function Controller:TransitionSound(path)
	self.transitionSounds[#self.transitionSounds + 1] = path
	PlayToAll(path)
end

-- The transition's opening cues: the map's description in the chat, with
-- the seconds left, the matchmaking sting and the announcer.
function Controller:Opening()
	local title, lines = Gameplay.Describe(MapInfo())
	local left = math.ceil(self.mode:TransitionEnd() - CurTime())
	lines[#lines + 1] = string.format("Gameplay mode begins in %d seconds; then choose a team.", left)
	Chat(title, lines)
	self:TransitionSound(TRANSITION_MUSIC)
	self:TransitionSound(Pick(TRANSITION_VOICES))
end

-- The transition's clock, fed to the model each TRANSITION_TICK.
function Controller:OpenClock()
	self.transitionSounds = {}
	timer.Create(TRANSITION_TIMER, TRANSITION_TICK, 0, function() self:Tick() end)
end

-- A request's transition: its clock and its opening cues at once.
function Controller:OpenTransition()
	self:OpenClock()
	self:Opening()
end

-- Calls off the transition, silencing what it played.
function Controller:CancelTransition()
	timer.Remove(TRANSITION_TIMER)
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
	[Gamemode.STOP_WAITING] = function() timer.Remove(WAIT_TIMER) end,
}

-- story: the requester's own notice, { title, lines } for the chat and
-- announcement for everyone's screen (the AI war's).
local NOTICES = {
	[Gamemode.NOTICE_NONE] = function() end,
	[Gamemode.NOTICE_REQUEST_CHAT] = function(_, story) Chat(story.title, story.lines) end,
	[Gamemode.NOTICE_REQUEST_ANNOUNCEMENT] = function(_, story) WS.Announce(story.announcement) end,
	[Gamemode.NOTICE_CALLED_OFF] = function()
		Chat("Game called off. Carry on.", { })
		PlayToAll(CALLED_OFF_SFX)	
	end,
	[Gamemode.NOTICE_SANDBOX] = function()
		PlayToAll(Pick(SANDBOX_SOUNDS))
		WS.Announce("Gameplay mode has ended. Sandbox mode until a new game begins.")
	end,
	[Gamemode.NOTICE_REFUSED] = function(requester, _, refusal) Tell(requester, "Gameplay: " .. refusal) end,
	[Gamemode.NOTICE_WAITING] = function()
		local have, need = PlayersNeeded()
		WS.Announce(string.format("Waiting for players (%d/%d): the game begins once they are here.", have, need))
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
	[Gamemode.CUE_OPENING] = function(self) self:Opening() end,
	[Gamemode.CUE_COUNT] = function(self, cue)
		if ADMIN_LINES[cue.left] then self:TransitionSound(ADMIN_LINES[cue.left]) end
	end,
	[Gamemode.CUE_ADMIN_LINE] = function() PlayToAll(ADMIN_LINES[0]) end,
	[Gamemode.CUE_BEGIN] = function(self)
		timer.Remove(TRANSITION_TIMER)
		self.transitionSounds = {}
		-- a second on, so the announcer's "Fight!" is heard before the round restarts
		timer.Simple(1, function()
			self:Begin()
		end)
	end,
}

-- A map's load countdown is cut short once the players expected from the
-- previous map are in (foundation.gamemode's Hurry; ws/sv_arrivals.lua).
function Controller:Tick()
	local now = CurTime()
	if WS.ExpectedPlayersIn() then self.mode:Hurry(now) end
	for _, cue in ipairs(self.mode:Advance(now)) do CUES[cue.kind](self, cue) end
	self:Publish()
end

-- Gameplay mode begins: a clean slate, everyone unassigned, the fallback
-- state of a fresh join; each client opens its team menu on seeing it.
function Controller:Begin()
	local rules = WS.Rules
	team.SetScore(WS.TEAM_RED, 0)
	team.SetScore(WS.TEAM_BLUE, 0)
	rules:Unhalt()
	rules:RestartRound()
	for _, ply in ipairs(player.GetAll()) do
		WS.SetPlayerTeam(ply, WS.TEAM_UNASSIGNED, true)
	end
	-- JC: Hidden because too much visual clutte
	-- Center("Choose a team!")
end

-- A map with rounds starts in the mode sv_gameplay_enabled holds: Sandbox
-- mode halts the rounds; Gameplay mode counts down while the players load
-- (foundation.gamemode's Load), or waits for the players its mode needs,
-- the rounds halted until it begins. Rounds loaded for a game counting
-- down (a map without them) stay halted until it begins.
function Controller:StartAtLoad()
	ACTIONS[self.mode:Load(CurTime(), PlayersReady()).action](self)
	if self.mode:Mode() ~= Gamemode.GAMEPLAY then WS.Rules:Halt() end
	self:Publish()
end

return Controller
