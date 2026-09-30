-- The gamemode feature's controller: owns the foundation.gamemode model,
-- the gamemode's Sandbox or Gameplay mode, and turns its answers into the
-- rounds, sounds, notices and the sv_gameplay_enabled setting. The Gameplay
-- Settings' Begin Game and Stop Game buttons, an admin setting
-- sv_gameplay_enabled in the console, and the AI war all make requests
-- (Request). Sandbox mode is tf_gamerules' Halt (no rounds, timers paused,
-- spawn doors and forcefields open); a map with rounds starts in the mode
-- the setting holds (StartAtLoad). The transition to Gameplay mode owns
-- every cue, whoever asked: the map's description in the chat, the
-- matchmaking start sting and the announcer's tournament-start line, the
-- countdown on screen (the announcer speaking the last numbers) and the
-- Administrator's line; then Begin: the scores cleared, the round system
-- restarted from scratch (RestartRound's full reset, as a map's first round)
-- and everyone a spectator with the team menu open until they choose a team.
local Gamemode = WETSAND.require("foundation.gamemode")
local Gameplay = WETSAND.require("foundation.gameplay")

-- Both made in wetsand/sh_gameplay.lua.
local ENABLED = GetConVar("sv_gameplay_enabled")
local SANDBOX_DISABLED = GetConVar("sv_gameplay_disable_sandbox")

local CHAT_NET, STOP_SOUNDS_NET = "wetsand_gameplay_chat", "wetsand_gameplay_stop_sounds"
util.AddNetworkString(CHAT_NET)
util.AddNetworkString(STOP_SOUNDS_NET)

local TRANSITION_TIMER = "wetsand_gamemode_transition"
local TRANSITION_TICK = 0.1 -- seconds between feeding the model the time; it cues on whole seconds

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
local TRANSITION_MUSIC = "ui/mm_round_start_casual.wav"
local TRANSITION_VOICES = {
	"vo/announcer_tournament_started1.mp3",
	"vo/announcer_tournament_started2.mp3",
	"vo/announcer_tournament_started3.mp3",
	"vo/announcer_tournament_started4.mp3",
}
local CALLED_OFF_SFX = "ui/vote_failure.wav"
local ADMIN_LINE_COUNT = 13
local ADMIN_LINES = {}
for i = 1, ADMIN_LINE_COUNT do ADMIN_LINES[i] = string.format("vo/compmode/cm_admin_compbeginsstart_%02d.mp3", i) end

local Controller = {
	mode = Gamemode.New(IsValid(WETSAND.Rules), ENABLED:GetBool()),
	transitionSounds = {}, -- what the transition has played, to silence if it is called off
}

local function PlayToAll(path)
	WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, path)
end

local function Pick(list)
	return list[math.random(#list)]
end

-- A requester is a player, or nil for the server console.
local function Tell(requester, text)
	if IsValid(requester) then requester:ChatPrint(text) else print(text) end
end

-- A title and lines in every player's chat (the client colours the title).
local function Chat(title, lines)
	net.Start(CHAT_NET)
	net.WriteString(title)
	net.WriteUInt(#lines, 8)
	for _, line in ipairs(lines) do net.WriteString(line) end
	net.Broadcast()
end

local function Center(text)
	for _, ply in ipairs(player.GetAll()) do ply:PrintMessage(HUD_PRINTCENTER, text) end
end

-- What the map plays, for foundation.gameplay.
local function MapInfo()
	return {
		map = game.GetMap(),
		trains = #ents.FindByClass("team_train_watcher"),
		race = #ents.FindByClass("tf_logic_multiple_escort") > 0,
		points = #ents.FindByClass("team_control_point"),
		rounds = #ents.FindByClass("team_control_point_round"),
		flags = #ents.FindByClass("item_teamflag"),
	}
end

-- sv_gameplay_enabled follows a settled mode; the transition leaves it.
function Controller:Publish()
	local setting = Gamemode.SETTING[self.mode:Mode()]
	if setting ~= nil and ENABLED:GetBool() ~= setting then ENABLED:SetBool(setting) end
end

-- A transition sound, remembered so Stop Game can silence it.
function Controller:TransitionSound(path)
	self.transitionSounds[#self.transitionSounds + 1] = path
	PlayToAll(path)
end

-- The transition's opening cues, then its clock.
function Controller:OpenTransition()
	self.transitionSounds = {}
	local title, lines = Gameplay.Describe(MapInfo())
	lines[#lines + 1] = string.format("Gameplay mode begins in %d seconds; then choose a team.", Gamemode.ADMIN_LINE_AT)
	Chat(title, lines)
	self:TransitionSound(TRANSITION_MUSIC)
	self:TransitionSound(Pick(TRANSITION_VOICES))
	timer.Create(TRANSITION_TIMER, TRANSITION_TICK, 0, function() self:Tick() end)
end

-- Calls off the transition, silencing what it played.
function Controller:CancelTransition()
	timer.Remove(TRANSITION_TIMER)
	net.Start(STOP_SOUNDS_NET)
	net.WriteUInt(#self.transitionSounds, 8)
	for _, path in ipairs(self.transitionSounds) do net.WriteString(path) end
	net.Broadcast()
	self.transitionSounds = {}
end

local ACTIONS = {
	[Gamemode.STAY] = function() end,
	[Gamemode.START_TRANSITION] = function(self) self:OpenTransition() end,
	[Gamemode.CANCEL_TRANSITION] = function(self) self:CancelTransition() end,
	[Gamemode.ENTER_SANDBOX] = function() WETSAND.Rules:Halt() end,
}

-- story: the requester's own notice, { title, lines } for the chat and
-- announcement for everyone's screen (the AI war's).
local NOTICES = {
	[Gamemode.NOTICE_NONE] = function() end,
	[Gamemode.NOTICE_REQUEST_CHAT] = function(_, story) Chat(story.title, story.lines) end,
	[Gamemode.NOTICE_REQUEST_ANNOUNCEMENT] = function(_, story) WETSAND.Announce(story.announcement) end,
	[Gamemode.NOTICE_CALLED_OFF] = function()
		Chat("Game called off. Carry on.", { })
		PlayToAll(CALLED_OFF_SFX)	
	end,
	[Gamemode.NOTICE_SANDBOX] = function()
		PlayToAll(Pick(SANDBOX_SOUNDS))
		WETSAND.Announce("Gameplay mode has ended. Sandbox mode until a new game begins.")
	end,
	[Gamemode.NOTICE_REFUSED] = function(requester, _, refusal) Tell(requester, "Gameplay: " .. refusal) end,
	[Gamemode.NOTICE_DENIED] = function(requester, _, refusal)
		Tell(requester, "Gameplay: " .. refusal)
		if IsValid(requester) then WETSAND.PlaySoundTo(requester, requester, Gamemode.DENY_SOUND) end
	end,
}

-- want: Gamemode.SANDBOX or GAMEPLAY; source: a Gamemode.SOURCE_*;
-- requester: the player who asked, or nil for the server console; story as
-- NOTICES takes it. Returns true, or false and why not (the requester has
-- been told, when the model says so).
function Controller:Request(want, source, requester, story)
	local answer = self.mode:Request(want, source, CurTime(), SANDBOX_DISABLED:GetBool())
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
	[Gamemode.CUE_COUNT] = function(self, cue)
		Center("Gameplay mode in " .. cue.left)
		if cue.spoken then self:TransitionSound("Announcer.RoundBegins" .. cue.left .. "Seconds") end
	end,
	[Gamemode.CUE_ADMIN_LINE] = function() PlayToAll(Pick(ADMIN_LINES)) end,
	[Gamemode.CUE_BEGIN] = function(self)
		timer.Remove(TRANSITION_TIMER)
		self.transitionSounds = {}
		self:Begin()
	end,
}

function Controller:Tick()
	for _, cue in ipairs(self.mode:Advance(CurTime())) do CUES[cue.kind](self, cue) end
	self:Publish()
end

-- Gameplay mode begins: a clean slate, everyone choosing a team.
function Controller:Begin()
	local rules = WETSAND.Rules
	team.SetScore(WETSAND.TEAM_RED, 0)
	team.SetScore(WETSAND.TEAM_BLUE, 0)
	rules:Unhalt()
	rules:RestartRound()
	for _, ply in ipairs(player.GetAll()) do
		WETSAND.SetPlayerTeam(ply, WETSAND.TEAM_SPECTATOR, true)
		WETSAND.ShowTeamMenu(ply)
	end
	-- Center("Choose a team!")
end

-- A map with rounds starts in the mode sv_gameplay_enabled holds, quietly:
-- Sandbox mode halts the rounds, Gameplay mode leaves the map's own round start.
function Controller:StartAtLoad()
	if self.mode:Mode() == Gamemode.SANDBOX then WETSAND.Rules:Halt() end
end

return Controller
