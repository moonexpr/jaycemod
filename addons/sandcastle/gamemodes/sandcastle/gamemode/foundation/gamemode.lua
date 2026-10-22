-- The gamemode's own mode, above the round system: Sandbox mode (no rounds,
-- spawn doors open, the map played like Sandbox), Gameplay mode (the rounds
-- run), and the transition between them, a countdown that ends by beginning
-- Gameplay mode. The round system's own states are a consequence the
-- controller drives, not part of this model. The server setting
-- sv_gameplay_enabled holds the settled mode across map changes (SETTING),
-- so a map with rounds starts in it; a map without rounds stays in Sandbox
-- mode until a game begins: a request for Gameplay mode there loads the
-- rounds (loadRounds: untimed, to the round limits) and counts down as on a
-- map with rounds, which it is from then on.
--
-- A request asks for a mode and carries its source: the Begin Game button,
-- Stop Game and the console's sv_gameplay_enabled are SOURCE_BUTTON or
-- SOURCE_CONSOLE, the AI war SOURCE_AI_WAR (only ever asking for Gameplay
-- mode). With sv_gameplay_disable_sandbox on, nothing enters Sandbox mode.
-- Each answer says what the controller does, which notice the requester
-- gets, and, when nothing changes, why.
--
-- A game begins only once the round mode's player requirement is met
-- (mp_waitingforplayers): each request says whether it is (ready). Until
-- then the map waits (WAITING), played as Sandbox mode, and the countdown
-- starts by itself once the controller reports the players there
-- (Players); a map loading in Gameplay mode without them waits too (Load).
-- Once Gameplay mode has begun, players leaving change nothing.
--
-- A map loading in Gameplay mode (a map change) counts down too, longer, as
-- its players are still loading (Load: LOAD_COUNTDOWN), and the controller
-- cuts it short once those expected from the previous map are in (Hurry:
-- HURRIED_COUNTDOWN). A requested countdown keeps its length.
--
-- Every countdown readies the game in stages, each cued once as the time
-- left reaches it (a request's first two as it starts): the map cleaned up
-- CLEANUP_AT seconds before its end, the match announced at ANNOUNCE_AT,
-- then the first pre-round PREROUND_AT seconds before it, everyone on a
-- team, respawned and held, so the round runs as the countdown ends.
--
-- The transition's timing lives here; the controller feeds it the time
-- (Advance) and plays the cues it returns.
local ceil, ipairs, max, min, setmetatable = math.ceil, ipairs, math.max, math.min, setmetatable
local Cfsm = require("foundation.core.cfsm")
module(...)

-- Modes.
SANDBOX, TRANSITION, GAMEPLAY, WAITING = 0, 1, 2, 3

-- sv_gameplay_enabled for each settled mode; the transition and the wait
-- leave it as it was.
SETTING = {
	[SANDBOX] = false,
	[GAMEPLAY] = true,
}

-- Who asks.
SOURCE_BUTTON, SOURCE_CONSOLE, SOURCE_AI_WAR = "button", "console", "ai_war"

-- What the controller does on an answer.
STAY = "stay" -- nothing changes
START_TRANSITION = "start_transition" -- the transition's opening cues, then its countdown
START_LOAD_COUNTDOWN = "start_load_countdown" -- the load's countdown, its opening cued later (CUE_OPENING)
CANCEL_TRANSITION = "cancel_transition" -- silence the countdown; halt the rounds, a pre-round it began too
ENTER_SANDBOX = "enter_sandbox" -- halt the rounds
WAIT = "wait" -- wait for players, the rounds halted
STOP_WAITING = "stop_waiting" -- the wait called off; the rounds stayed halted

-- Which notice the requester gets.
NOTICE_NONE = "none"
NOTICE_REQUEST_CHAT = "request_chat" -- the requester's details in the chat
NOTICE_REQUEST_ANNOUNCEMENT = "request_announcement" -- the requester's announcement
NOTICE_CALLED_OFF = "called_off" -- the countdown was called off
NOTICE_SANDBOX = "sandbox" -- Gameplay mode ended
NOTICE_REFUSED = "refused" -- the requester is told why not
NOTICE_DENIED = "denied" -- told why not, with DENY_SOUND
NOTICE_WAITING = "waiting" -- everyone is told the game waits for players

-- HL2's locked-button deny.
DENY_SOUND = "buttons/button10.wav"

-- Why an answer changes nothing.
NO_ROUNDS = "this map has no rounds"
ALREADY_COUNTING = "Gameplay mode is already counting down"
ALREADY_WAITING = "Gameplay mode is already waiting for players"
ALREADY_GAMEPLAY = "already in Gameplay mode"
ALREADY_SANDBOX = "already in Sandbox mode"
SANDBOX_DISABLED = "Sandbox mode is disabled (sv_gameplay_disable_sandbox 1)"

-- The transition: a count each second down to 1, the last SPOKEN_COUNT
-- spoken (the announcer's lines exist for 5..1), and at its end
-- (TransitionEnd, which the round timer shows) the Administrator's line and
-- Gameplay mode. A request's lasts ADMIN_LINE_AT seconds, counting from
-- COUNTDOWN; a map's load LOAD_COUNTDOWN, or HURRIED_COUNTDOWN from when its
-- expected players are in, if that is sooner.
COUNTDOWN = 12
SPOKEN_COUNT = 5
ADMIN_LINE_AT = 13
LOAD_COUNTDOWN = 180
HURRIED_COUNTDOWN = 30
CLEANUP_AT = ADMIN_LINE_AT + 1
ANNOUNCE_AT = ADMIN_LINE_AT
PREROUND_AT = 10

-- Cues Advance returns, in order.
CUE_OPENING = "opening" -- the load countdown's opening cues, as a request's (START_TRANSITION)
CUE_CLEANUP = "cleanup" -- the map cleaned up, the rounds still halted
CUE_ANNOUNCE = "announce" -- the match announced: the matchmaking sting and the announcer
CUE_PREROUND = "preround" -- everyone on a team: the first pre-round, held until CUE_BEGIN
CUE_COUNT = "count" -- { kind, left, spoken }
CUE_ADMIN_LINE = "admin_line"
CUE_BEGIN = "begin" -- Gameplay mode begins: the pre-round's round runs

-- The countdown's stages, by the seconds left they come at, latest last.
local STAGES = {
	{ kind = CUE_CLEANUP, at = CLEANUP_AT },
	{ kind = CUE_ANNOUNCE, at = ANNOUNCE_AT },
	{ kind = CUE_PREROUND, at = PREROUND_AT },
}

local function Answer(action, notice, refusal, loadRounds)
	return {
		action = action,
		notice = notice,
		refusal = refusal,
		loadRounds = loadRounds,
	}
end

local SOURCES = { SOURCE_BUTTON, SOURCE_CONSOLE, SOURCE_AI_WAR }

-- A row of answers by source: every source gets answer, but the AI war gets
-- aiWar when given (a refusal it is not told of: the war goes on).
local function BySource(answer, aiWar)
	local row = {}
	for _, source in ipairs(SOURCES) do row[source] = answer end
	row[SOURCE_AI_WAR] = aiWar or answer
	return row
end

local QUIET = Answer(STAY, NOTICE_NONE)

-- RULES[wanted mode][current mode][source]
local RULES = {
	[GAMEPLAY] = {
		[SANDBOX] = BySource(Answer(START_TRANSITION, NOTICE_NONE), Answer(START_TRANSITION, NOTICE_REQUEST_CHAT)),
		[TRANSITION] = BySource(Answer(STAY, NOTICE_REFUSED, ALREADY_COUNTING), Answer(STAY, NOTICE_REQUEST_CHAT)),
		[GAMEPLAY] = BySource(Answer(STAY, NOTICE_REFUSED, ALREADY_GAMEPLAY), Answer(STAY, NOTICE_REQUEST_ANNOUNCEMENT)),
		[WAITING] = BySource(Answer(STAY, NOTICE_REFUSED, ALREADY_WAITING), Answer(STAY, NOTICE_REQUEST_CHAT)),
	},
	[SANDBOX] = {
		[SANDBOX] = BySource(Answer(STAY, NOTICE_REFUSED, ALREADY_SANDBOX), QUIET),
		[TRANSITION] = BySource(Answer(CANCEL_TRANSITION, NOTICE_CALLED_OFF)),
		[GAMEPLAY] = BySource(Answer(ENTER_SANDBOX, NOTICE_SANDBOX)),
		[WAITING] = BySource(Answer(STOP_WAITING, NOTICE_CALLED_OFF)),
	},
}

-- Without rounds: Gameplay mode loads them; Sandbox mode is already so.
local WITHOUT_ROUNDS = {
	[GAMEPLAY] = BySource(Answer(START_TRANSITION, NOTICE_NONE, nil, true), Answer(START_TRANSITION, NOTICE_REQUEST_CHAT, nil, true)),
	[SANDBOX] = BySource(Answer(STAY, NOTICE_REFUSED, NO_ROUNDS), Answer(STAY, NOTICE_NONE, NO_ROUNDS)),
}
local SANDBOX_OFF = BySource(Answer(STAY, NOTICE_DENIED, SANDBOX_DISABLED))

local NEXT_MODE = {
	[START_TRANSITION] = TRANSITION,
	[CANCEL_TRANSITION] = SANDBOX,
	[ENTER_SANDBOX] = SANDBOX,
	[WAIT] = WAITING,
	[STOP_WAITING] = SANDBOX,
}

-- The modes and the only moves between them: the transition starts from
-- Sandbox mode or the wait, or Gameplay mode at load, and ends in Gameplay
-- mode or, called off, back in Sandbox; the wait starts from Sandbox mode,
-- or Gameplay mode at load.
local MODES = Cfsm.Define({
	name = "gamemode",
	states = { SANDBOX, TRANSITION, GAMEPLAY, WAITING },
	transitions = {
		[SANDBOX] = { TRANSITION, WAITING },
		[TRANSITION] = { SANDBOX, GAMEPLAY },
		[GAMEPLAY] = { SANDBOX, WAITING, TRANSITION },
		[WAITING] = { TRANSITION, SANDBOX },
	},
})

local Mode = {}
Mode.__index = Mode

-- hasRounds: the map's gamerules run rounds (TF2's, or a game begun).
-- enabled: sv_gameplay_enabled at map load.
function New(hasRounds, enabled)
	return setmetatable({
		hasRounds = hasRounds,
		modes = MODES:New((hasRounds and enabled) and GAMEPLAY or SANDBOX),
		loaded = false, -- Load has run
		endsAt = 0, -- when the transition ends
		cued = 0, -- the lowest count already cued (the transition's length before any)
		atLoad = false, -- the transition is the map's load's, which Hurry may cut short
		opened = false, -- its opening cues have played
		stage = 1, -- the next of STAGES to cue
	}, Mode)
end

function Mode:Mode()
	return self.modes:State()
end

-- sv_gameplay_enabled was set to enabled: the mode that asks for, or nil
-- when the settled mode already holds it (our own write, or no change).
function Mode:SettingWants(enabled)
	if SETTING[self:Mode()] == enabled then return nil end
	return enabled and GAMEPLAY or SANDBOX
end

local function Decide(self, want, source, sandboxDisabled)
	if not self.hasRounds then
		local answer = WITHOUT_ROUNDS[want][source]
		if answer.loadRounds then self.hasRounds = true end
		return answer
	end
	local mode = self:Mode()
	if want == SANDBOX and sandboxDisabled and mode ~= SANDBOX then return SANDBOX_OFF[source] end
	return RULES[want][mode][source]
end

-- A countdown of length seconds from now.
-- A request's opens as it starts; the load's later (CUE_OPENING).
local function Start(self, now, length, atLoad)
	self.endsAt = now + length
	self.cued = length
	self.atLoad = atLoad
	self.opened = not atLoad
	self.stage = 1
end

local function Apply(self, answer, now)
	if answer.action == START_TRANSITION then Start(self, now, ADMIN_LINE_AT, false) end
	local nextMode = NEXT_MODE[answer.action]
	if nextMode then self.modes:Enter(nextMode) end
	return answer
end

-- A request for mode want (SANDBOX or GAMEPLAY) from source at time now;
-- sandboxDisabled is sv_gameplay_disable_sandbox, ready whether the round
-- mode's player requirement is met. Returns the answer:
-- { action, notice, refusal }, refusal nil when granted.
function Mode:Request(want, source, now, sandboxDisabled, ready)
	local answer = Decide(self, want, source, sandboxDisabled)
	-- the rounds still load for a game that waits
	if answer.action == START_TRANSITION and not ready then answer = Answer(WAIT, NOTICE_WAITING, nil, answer.loadRounds) end
	return Apply(self, answer, now)
end

local START_ANSWER = Answer(START_TRANSITION, NOTICE_NONE)

-- Whether the player requirement is met at time now: met while waiting,
-- the countdown starts (START_TRANSITION); else nothing changes (STAY).
function Mode:Players(ready, now)
	if not (ready and self.modes:Is(WAITING)) then return QUIET end
	return Apply(self, START_ANSWER, now)
end

local WAIT_ANSWER = Answer(WAIT, NOTICE_NONE)

local LOAD_ANSWER = Answer(START_LOAD_COUNTDOWN, NOTICE_NONE)

-- The map has loaded, at time now; ready whether the round mode's player
-- requirement is met. A map loading in Gameplay mode counts down
-- LOAD_COUNTDOWN seconds (START_LOAD_COUNTDOWN), or without its players
-- waits for them (WAIT); anything else, or a second Load, changes nothing
-- (STAY).
function Mode:Load(now, ready)
	if self.loaded then return QUIET end
	self.loaded = true
	if self:Mode() ~= GAMEPLAY then return QUIET end
	if not ready then
		self.modes:Enter(WAITING)
		return WAIT_ANSWER
	end
	Start(self, now, LOAD_COUNTDOWN, true)
	self.modes:Enter(TRANSITION)
	return LOAD_ANSWER
end

-- The players expected from the previous map are in, at time now: the
-- load's countdown, with more than HURRIED_COUNTDOWN seconds left, ends
-- HURRIED_COUNTDOWN from now, the time left cued at once. Returns whether
-- its end moved.
function Mode:Hurry(now)
	if not (self.atLoad and self.modes:Is(TRANSITION)) then return false end
	if self.endsAt - now <= HURRIED_COUNTDOWN then return false end
	self.endsAt = now + HURRIED_COUNTDOWN
	self.cued = HURRIED_COUNTDOWN + 1
	return true
end

-- When the transition ends and Gameplay mode begins (the time Advance
-- returns CUE_BEGIN), or nil outside the transition.
function Mode:TransitionEnd()
	if not self.modes:Is(TRANSITION) then return nil end
	return self.endsAt
end

-- The stages due with left seconds left, each once, before that second's count.
local function Stages(self, cues, left)
	while STAGES[self.stage] and left <= STAGES[self.stage].at do
		cues[#cues + 1] = { kind = STAGES[self.stage].kind }
		self.stage = self.stage + 1
	end
end

-- The transition's cues due by time now since the last call, in order: the
-- load countdown's opening once its players are in (Hurry) or
-- HURRIED_COUNTDOWN seconds before its end; a count for each whole second
-- left passed, a stage before the count it comes at; at its end the last,
-- CUE_BEGIN, puts the model in Gameplay mode. None outside the transition.
function Mode:Advance(now)
	local cues = {}
	if not self.modes:Is(TRANSITION) then return cues end
	if not self.opened and self.endsAt - now <= HURRIED_COUNTDOWN then
		self.opened = true
		cues[1] = { kind = CUE_OPENING }
	end
	local left = max(ceil(self.endsAt - now), 0)
	for count = self.cued - 1, max(left, 1), -1 do
		Stages(self, cues, count)
		cues[#cues + 1] = {
			kind = CUE_COUNT,
			left = count,
			spoken = count <= SPOKEN_COUNT,
		}
	end
	Stages(self, cues, left)
	self.cued = min(self.cued, max(left, 1))
	if left == 0 then
		cues[#cues + 1] = { kind = CUE_ADMIN_LINE }
		cues[#cues + 1] = { kind = CUE_BEGIN }
		self.modes:Enter(GAMEPLAY)
	end
	return cues
end
