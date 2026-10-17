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
-- The transition's timing lives here; the controller feeds it the time
-- (Advance) and plays the cues it returns.
local floor, ipairs, min, setmetatable = math.floor, ipairs, math.min, setmetatable
local Cfsm = require("foundation.core.cfsm")
module(...)

-- Modes.
SANDBOX, TRANSITION, GAMEPLAY = 0, 1, 2

-- sv_gameplay_enabled for each settled mode; the transition leaves it as it was.
SETTING = {
	[SANDBOX] = false,
	[GAMEPLAY] = true,
}

-- Who asks.
SOURCE_BUTTON, SOURCE_CONSOLE, SOURCE_AI_WAR = "button", "console", "ai_war"

-- What the controller does on an answer.
STAY = "stay" -- nothing changes
START_TRANSITION = "start_transition" -- the transition's opening cues, then its countdown
CANCEL_TRANSITION = "cancel_transition" -- silence the countdown; the rounds stayed halted
ENTER_SANDBOX = "enter_sandbox" -- halt the rounds

-- Which notice the requester gets.
NOTICE_NONE = "none"
NOTICE_REQUEST_CHAT = "request_chat" -- the requester's details in the chat
NOTICE_REQUEST_ANNOUNCEMENT = "request_announcement" -- the requester's announcement
NOTICE_CALLED_OFF = "called_off" -- the countdown was called off
NOTICE_SANDBOX = "sandbox" -- Gameplay mode ended
NOTICE_REFUSED = "refused" -- the requester is told why not
NOTICE_DENIED = "denied" -- told why not, with DENY_SOUND

-- HL2's locked-button deny.
DENY_SOUND = "buttons/button10.wav"

-- Why an answer changes nothing.
NO_ROUNDS = "this map has no rounds (no tf_gamerules)"
ALREADY_COUNTING = "Gameplay mode is already counting down"
ALREADY_GAMEPLAY = "already in Gameplay mode"
ALREADY_SANDBOX = "already in Sandbox mode"
SANDBOX_DISABLED = "Sandbox mode is disabled (sv_gameplay_disable_sandbox 1)"

-- The transition: a count each second from COUNTDOWN down to 1, the last
-- SPOKEN_COUNT spoken (the announcer's lines exist for 5..1), and at
-- ADMIN_LINE_AT seconds (TransitionEnd, which the round timer shows) the
-- Administrator's line and Gameplay mode.
COUNTDOWN = 12
SPOKEN_COUNT = 5
ADMIN_LINE_AT = 13

-- Cues Advance returns, in order.
CUE_COUNT = "count" -- { kind, left, spoken }
CUE_ADMIN_LINE = "admin_line"
CUE_BEGIN = "begin" -- Gameplay mode begins: the rounds restart

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
	},
	[SANDBOX] = {
		[SANDBOX] = BySource(Answer(STAY, NOTICE_REFUSED, ALREADY_SANDBOX), QUIET),
		[TRANSITION] = BySource(Answer(CANCEL_TRANSITION, NOTICE_CALLED_OFF)),
		[GAMEPLAY] = BySource(Answer(ENTER_SANDBOX, NOTICE_SANDBOX)),
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
}

-- The modes and the only moves between them: the transition starts from
-- Sandbox mode, and ends in Gameplay mode or, called off, back in Sandbox.
local MODES = Cfsm.Define({
	name = "gamemode",
	states = { SANDBOX, TRANSITION, GAMEPLAY },
	transitions = {
		[SANDBOX] = { TRANSITION },
		[TRANSITION] = { SANDBOX, GAMEPLAY },
		[GAMEPLAY] = { SANDBOX },
	},
})

local Mode = {}
Mode.__index = Mode

-- hasRounds: the map has a round system to run (a tf_gamerules).
-- enabled: sv_gameplay_enabled at map load.
function New(hasRounds, enabled)
	return setmetatable({
		hasRounds = hasRounds,
		modes = MODES:New((hasRounds and enabled) and GAMEPLAY or SANDBOX),
		startedAt = 0, -- when the transition started
		counted = 0, -- the transition's seconds already cued
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

-- A request for mode want (SANDBOX or GAMEPLAY) from source at time now;
-- sandboxDisabled is sv_gameplay_disable_sandbox. Returns the answer:
-- { action, notice, refusal }, refusal nil when granted.
function Mode:Request(want, source, now, sandboxDisabled)
	local answer = Decide(self, want, source, sandboxDisabled)
	if answer.action == START_TRANSITION then
		self.startedAt = now
		self.counted = 0
	end
	local nextMode = NEXT_MODE[answer.action]
	if nextMode then self.modes:Enter(nextMode) end
	return answer
end

-- When the transition ends and Gameplay mode begins (the time Advance
-- returns CUE_BEGIN), or nil outside the transition.
function Mode:TransitionEnd()
	if not self.modes:Is(TRANSITION) then return nil end
	return self.startedAt + ADMIN_LINE_AT
end

-- The transition's cues due by time now since the last call, in order; the
-- last, CUE_BEGIN, puts the model in Gameplay mode. None outside the
-- transition.
function Mode:Advance(now)
	local cues = {}
	if not self.modes:Is(TRANSITION) then return cues end
	local reached = min(floor(now - self.startedAt), ADMIN_LINE_AT)
	for second = self.counted + 1, reached do
		if second <= COUNTDOWN then
			local left = COUNTDOWN - second + 1
			cues[#cues + 1] = {
				kind = CUE_COUNT,
				left = left,
				spoken = left <= SPOKEN_COUNT,
			}
		end
		if second == ADMIN_LINE_AT then
			cues[#cues + 1] = { kind = CUE_ADMIN_LINE }
			cues[#cues + 1] = { kind = CUE_BEGIN }
			self.modes:Enter(GAMEPLAY)
		end
	end
	self.counted = reached
	return cues
end
