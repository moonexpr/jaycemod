-- games.system.gamemode: the gamemode's own mode, Sandbox or Gameplay, and the
-- countdown between them, driven through whole scenarios with injected time.
local T = dofile("tests/harness.lua")
local Gamemode = system.gamemode

local ROUNDS, NO_ROUNDS = true, false
local ENABLED, DISABLED = true, false -- sv_gameplay_enabled at map load
local SANDBOX_ALLOWED, SANDBOX_OFF = false, true -- sv_gameplay_disable_sandbox
local READY, MISSING = true, false -- the mode's player requirement met, or not
local START = 100

local SANDBOX, GAMEPLAY, WAITING = Gamemode.SANDBOX, Gamemode.GAMEPLAY, Gamemode.WAITING
local BUTTON, CONSOLE, AI_WAR = Gamemode.SOURCE_BUTTON, Gamemode.SOURCE_CONSOLE, Gamemode.SOURCE_AI_WAR

-- The cues from START until the transition ends, each with the second it falls on.
local function RunCountdown(mode)
	local seen = {}
	for _, cue in ipairs(mode:Advance(START)) do
		cue.second = 0
		seen[#seen + 1] = cue
	end
	for second = 1, Gamemode.COUNTDOWN do
		for _, cue in ipairs(mode:Advance(START + second)) do
			cue.second = second
			seen[#seen + 1] = cue
		end
	end
	return seen
end

local function Kinds(cues, kind)
	local found = {}
	for _, cue in ipairs(cues) do
		if cue.kind == kind then found[#found + 1] = cue end
	end
	return found
end

local function InGameplay()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	RunCountdown(mode)
	return mode
end

local function Expect(answer, action, notice, refusal, what)
	T.eq(answer.action, action, what .. ": action")
	T.eq(answer.notice, notice, what .. ": notice")
	T.eq(answer.refusal, refusal, what .. ": refusal")
end

T.test("a map with rounds starts in the mode sv_gameplay_enabled holds; without rounds, in Sandbox mode", function()
	T.eq(Gamemode.New(ROUNDS, DISABLED):Mode(), SANDBOX, "setting off")
	T.eq(Gamemode.New(ROUNDS, ENABLED):Mode(), GAMEPLAY, "setting on: the map's normal round start")
	T.eq(Gamemode.New(NO_ROUNDS, ENABLED):Mode(), SANDBOX, "no rounds")
	T.eq(#Gamemode.New(ROUNDS, ENABLED):Advance(START + Gamemode.COUNTDOWN), 0, "no countdown at load")
end)

T.test("the setting reads each settled mode; the transition leaves it as it was", function()
	T.eq(Gamemode.SETTING[SANDBOX], false, "Sandbox mode")
	T.eq(Gamemode.SETTING[GAMEPLAY], true, "Gameplay mode")
	T.eq(Gamemode.SETTING[Gamemode.TRANSITION], nil, "the transition")
end)

T.test("a change to sv_gameplay_enabled the settled mode already holds asks nothing; any other asks for its mode", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	T.eq(mode:SettingWants(false), nil, "Sandbox mode, set to 0: our own write")
	T.eq(mode:SettingWants(true), GAMEPLAY, "Sandbox mode, set to 1")
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	T.eq(mode:SettingWants(true), GAMEPLAY, "during the transition, set to 1")
	T.eq(mode:SettingWants(false), SANDBOX, "during the transition, set to 0")
	RunCountdown(mode)
	T.eq(mode:SettingWants(true), nil, "Gameplay mode, set to 1: our own write")
	T.eq(mode:SettingWants(false), SANDBOX, "Gameplay mode, set to 0")
end)

T.test("the button in Sandbox mode starts the transition, which counts down and begins Gameplay mode", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	Expect(mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY), Gamemode.START_LOAD_COUNTDOWN, Gamemode.NOTICE_NONE, nil,
		"the long countdown opens when ready")
	T.eq(mode:Mode(), Gamemode.TRANSITION, "counting down")
	T.eq(mode:TransitionEnd(), START + Gamemode.LOAD_COUNTDOWN, "starts at 180 seconds")
	T.eq(#mode:Advance(START), 0, "opens quietly")
	local hurryAt = START + 10
	T.eq(mode:Hurry(hurryAt), true, "ready bots shorten it")
	local opening = mode:Advance(hurryAt)
	T.eq(opening[1].kind, Gamemode.CUE_OPENING, "opens when shortened")
	T.eq(opening[2].left, Gamemode.HURRIED_COUNTDOWN, "the final 30-second count")
	local cues = mode:Advance(hurryAt + Gamemode.HURRIED_COUNTDOWN)
	local counts = Kinds(cues, Gamemode.CUE_COUNT)
	T.eq(#counts, Gamemode.HURRIED_COUNTDOWN - 1, "counts the remaining seconds")
	T.eq(counts[#counts].left, 1, "last count")
	for _, count in ipairs(counts) do
		T.eq(count.spoken, count.left <= Gamemode.SPOKEN_COUNT, "spoken at " .. count.left)
	end
	local admin = Kinds(cues, Gamemode.CUE_ADMIN_LINE)
	T.eq(#admin, 1, "one Administrator line")
	local begin = Kinds(cues, Gamemode.CUE_BEGIN)
	T.eq(#begin, 1, "one begin")
	T.eq(cues[#cues], begin[1], "begin comes last")
	T.eq(mode:Mode(), GAMEPLAY, "in Gameplay mode")
	T.eq(#mode:Advance(hurryAt + Gamemode.HURRIED_COUNTDOWN + 5), 0, "nothing after it began")
end)

T.test("the console's sv_gameplay_enabled 1 is a request like the button", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	Expect(mode:Request(GAMEPLAY, CONSOLE, START, SANDBOX_ALLOWED, READY), Gamemode.START_LOAD_COUNTDOWN, Gamemode.NOTICE_NONE, nil,
		"from Sandbox mode")
	RunCountdown(mode)
	T.eq(mode:Mode(), GAMEPLAY, "in Gameplay mode")
end)

T.test("a late tick catches up on every cue it missed, in order", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	local opening = Kinds(mode:Advance(START + 0.5), Gamemode.CUE_COUNT)
	T.eq(#opening, 0, "the long countdown starts quietly")
	local at = START + 10
	mode:Hurry(at)
	local begun = mode:Advance(at)
	T.eq(begun[1].kind, Gamemode.CUE_OPENING, "opens after readiness")
	T.eq(begun[2].left, Gamemode.HURRIED_COUNTDOWN, "starts the final 30 seconds")
	local cues = mode:Advance(at + Gamemode.HURRIED_COUNTDOWN + 3)
	local counts = Kinds(cues, Gamemode.CUE_COUNT)
	T.eq(#counts, Gamemode.HURRIED_COUNTDOWN - 1, "every remaining count")
	T.eq(counts[1].left, Gamemode.HURRIED_COUNTDOWN - 1, "continues after the opening count")
	T.eq(#Kinds(cues, Gamemode.CUE_PREROUND), 1, "the pre-round")
	T.eq(cues[#cues].kind, Gamemode.CUE_BEGIN, "then begins")
	T.eq(mode:Mode(), GAMEPLAY, "in Gameplay mode")
end)

-- Where each cue falls: its index in cues, and for a count its seconds left.
local function Positions(cues)
	local at = { count = {} }
	for i, cue in ipairs(cues) do
		if cue.kind == Gamemode.CUE_COUNT then at.count[cue.left] = i else at[cue.kind] = i end
	end
	return at
end

T.test("a requested countdown cleans up before its last stretch and holds the pre-round", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	local first = mode:Advance(START + 0.1)
	T.eq(#Kinds(first, Gamemode.CUE_CLEANUP), 0, "not cleaned up at the opening")
	T.eq(#Kinds(first, Gamemode.CUE_ANNOUNCE), 0, "not announced at the opening")
	local cues = {}
	for _, cue in ipairs(first) do
		cue.second = 0
		cues[#cues + 1] = cue
	end
	for second = 1, Gamemode.COUNTDOWN do
		for _, cue in ipairs(mode:Advance(START + second)) do
			cue.second = second
			cues[#cues + 1] = cue
		end
	end
	T.eq(#Kinds(cues, Gamemode.CUE_CLEANUP), 1, "cleaned up once")
	T.eq(#Kinds(cues, Gamemode.CUE_ANNOUNCE), 1, "announced once")
	T.eq(Kinds(cues, Gamemode.CUE_CLEANUP)[1].second, Gamemode.COUNTDOWN - Gamemode.CLEANUP_AT, "cleanup timing")
	T.eq(Kinds(cues, Gamemode.CUE_ANNOUNCE)[1].second, Gamemode.COUNTDOWN - Gamemode.ANNOUNCE_AT, "announcement timing")
	local preround = Kinds(cues, Gamemode.CUE_PREROUND)
	T.eq(#preround, 1, "one pre-round")
	T.eq(preround[1].second, Gamemode.COUNTDOWN - Gamemode.PREROUND_AT, "PREROUND_AT seconds before the end")
	local at = Positions(cues)
	T.eq(at[Gamemode.CUE_PREROUND] < at.count[Gamemode.PREROUND_AT], true, "with its count")
	T.eq(at[Gamemode.CUE_PREROUND] > at.count[Gamemode.PREROUND_AT + 1], true, "after the count before")
end)

T.test("a load countdown cleans the map up CLEANUP_AT seconds before its end, then the pre-round", function()
	local mode = Gamemode.New(ROUNDS, ENABLED)
	mode:Load(START, READY)
	local finish = START + Gamemode.LOAD_COUNTDOWN
	T.eq(#Kinds(mode:Advance(finish - Gamemode.CLEANUP_AT - 0.5), Gamemode.CUE_CLEANUP), 0, "not yet")
	local cues = mode:Advance(finish - Gamemode.CLEANUP_AT)
	T.eq(cues[1].kind, Gamemode.CUE_CLEANUP, "cleans up")
	T.eq(cues[2].left, Gamemode.CLEANUP_AT, "with its count")
	T.eq(#Kinds(cues, Gamemode.CUE_ANNOUNCE), 0, "announced later")
	local announced = mode:Advance(finish - Gamemode.ANNOUNCE_AT)
	T.eq(announced[1].kind, Gamemode.CUE_ANNOUNCE, "announced")
	T.eq(announced[2].left, Gamemode.ANNOUNCE_AT, "with its count")
	local rest = mode:Advance(finish)
	local at = Positions(rest)
	T.eq(#Kinds(rest, Gamemode.CUE_CLEANUP), 0, "once")
	T.eq(at[Gamemode.CUE_PREROUND] < at.count[Gamemode.PREROUND_AT], true, "the pre-round with its count")
	T.eq(at[Gamemode.CUE_PREROUND] < at[Gamemode.CUE_BEGIN], true, "before the begin")
end)

T.test("a countdown called off and asked for again cleans up and holds the pre-round again", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	local calledOff = START + Gamemode.COUNTDOWN - Gamemode.PREROUND_AT + 1
	mode:Advance(calledOff - 1)
	mode:Request(SANDBOX, BUTTON, calledOff, SANDBOX_ALLOWED, READY)
	local again = calledOff + 5
	mode:Request(GAMEPLAY, BUTTON, again, SANDBOX_ALLOWED, READY)
	local cues = mode:Advance(again + Gamemode.COUNTDOWN)
	T.eq(#Kinds(cues, Gamemode.CUE_CLEANUP), 1, "cleaned up")
	T.eq(#Kinds(cues, Gamemode.CUE_ANNOUNCE), 1, "announced")
	T.eq(#Kinds(cues, Gamemode.CUE_PREROUND), 1, "the pre-round")
end)

T.test("AI war in Sandbox mode starts the transition and leaves its details in the chat", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	Expect(mode:Request(GAMEPLAY, AI_WAR, START, SANDBOX_ALLOWED, READY), Gamemode.START_LOAD_COUNTDOWN,
		Gamemode.NOTICE_REQUEST_CHAT, nil, "chat, no announcement")
	T.eq(mode:Mode(), Gamemode.TRANSITION, "counting down")
end)

T.test("AI war during the transition joins it without restarting the countdown", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	mode:Hurry(START + 4)
	Expect(mode:Request(GAMEPLAY, AI_WAR, START + 4, SANDBOX_ALLOWED, READY), Gamemode.STAY, Gamemode.NOTICE_REQUEST_CHAT, nil,
		"already under way")
	local cues = mode:Advance(START + 5)
	local counts = Kinds(cues, Gamemode.CUE_COUNT)
	T.eq(counts[#counts].left, Gamemode.HURRIED_COUNTDOWN - 1, "the shortened countdown goes on")
end)

T.test("AI war in Gameplay mode is announced", function()
	local mode = InGameplay()
	Expect(mode:Request(GAMEPLAY, AI_WAR, START + 60, SANDBOX_ALLOWED, READY), Gamemode.STAY,
		Gamemode.NOTICE_REQUEST_ANNOUNCEMENT, nil, "announcement")
	T.eq(mode:Mode(), GAMEPLAY, "still in Gameplay mode")
end)

T.test("Stop during the transition calls it off and stays in Sandbox mode", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	mode:Advance(START + 3)
	Expect(mode:Request(SANDBOX, BUTTON, START + 3, SANDBOX_ALLOWED, READY), Gamemode.CANCEL_TRANSITION,
		Gamemode.NOTICE_CALLED_OFF, nil, "called off")
	T.eq(mode:Mode(), SANDBOX, "Sandbox mode")
	T.eq(#mode:Advance(START + Gamemode.COUNTDOWN + 1), 0, "no cues after it was called off")
	T.eq(mode:Mode(), SANDBOX, "never began")
end)

T.test("the transition ends when Gameplay mode begins; outside it there is no end to show", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	T.eq(mode:TransitionEnd(), nil, "Sandbox mode")
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	T.eq(mode:TransitionEnd(), START + Gamemode.COUNTDOWN, "counting down")
	mode:Advance(START + 4)
	T.eq(mode:TransitionEnd(), START + Gamemode.COUNTDOWN, "unmoved by the ticks")
	local begin = Kinds(mode:Advance(START + Gamemode.COUNTDOWN), Gamemode.CUE_BEGIN)
	T.eq(#begin, 1, "begins at that end")
	T.eq(mode:TransitionEnd(), nil, "Gameplay mode")
end)

T.test("a called-off transition has no end to show", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	mode:Request(SANDBOX, BUTTON, START + 3, SANDBOX_ALLOWED, READY)
	T.eq(mode:TransitionEnd(), nil, "called off")
	T.eq(Gamemode.New(ROUNDS, ENABLED):TransitionEnd(), nil, "Gameplay mode at load")
end)

T.test("a new transition after one was called off counts from its own start", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	mode:Request(SANDBOX, BUTTON, START + 6, SANDBOX_ALLOWED, READY)
	mode:Request(GAMEPLAY, BUTTON, START + 20, SANDBOX_ALLOWED, READY)
	T.eq(mode:TransitionEnd(), START + 20 + Gamemode.LOAD_COUNTDOWN, "the new long countdown")
	T.eq(#mode:Advance(START + 20), 0, "starts quietly")
end)

T.test("Stop in Gameplay mode, or the console's sv_gameplay_enabled 0, enters Sandbox mode with its notice", function()
	for _, source in ipairs({ BUTTON, CONSOLE }) do
		local mode = InGameplay()
		Expect(mode:Request(SANDBOX, source, START + 60, SANDBOX_ALLOWED, READY), Gamemode.ENTER_SANDBOX, Gamemode.NOTICE_SANDBOX,
			nil, source)
		T.eq(mode:Mode(), SANDBOX, "Sandbox mode, from " .. source)
	end
end)

T.test("the button in Gameplay mode or during the transition changes nothing and says why", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	Expect(mode:Request(GAMEPLAY, BUTTON, START + 2, SANDBOX_ALLOWED, READY), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
		Gamemode.ALREADY_COUNTING, "during the transition")
	RunCountdown(mode)
	Expect(mode:Request(GAMEPLAY, BUTTON, START + 60, SANDBOX_ALLOWED, READY), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
		Gamemode.ALREADY_GAMEPLAY, "in Gameplay mode")
	T.eq(mode:Mode(), GAMEPLAY, "still in Gameplay mode")
end)

T.test("Stop in Sandbox mode changes nothing and says why", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	Expect(mode:Request(SANDBOX, BUTTON, START, SANDBOX_ALLOWED, READY), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
		Gamemode.ALREADY_SANDBOX, "already")
end)

T.test("with sandbox disabled, no request enters Sandbox mode, and the requester is denied", function()
	for _, source in ipairs({ BUTTON, CONSOLE }) do
		local mode = InGameplay()
		Expect(mode:Request(SANDBOX, source, START + 60, SANDBOX_OFF, READY), Gamemode.STAY, Gamemode.NOTICE_DENIED,
			Gamemode.SANDBOX_DISABLED, "from Gameplay mode, " .. source)
		T.eq(mode:Mode(), GAMEPLAY, "still in Gameplay mode, " .. source)
	end
	local counting = Gamemode.New(ROUNDS, DISABLED)
	counting:Request(GAMEPLAY, BUTTON, START, SANDBOX_OFF, READY)
	Expect(counting:Request(SANDBOX, BUTTON, START + 3, SANDBOX_OFF, READY), Gamemode.STAY, Gamemode.NOTICE_DENIED,
		Gamemode.SANDBOX_DISABLED, "during the transition")
	T.eq(#Kinds(counting:Advance(START + Gamemode.COUNTDOWN), Gamemode.CUE_BEGIN), 1, "the countdown goes on")
	T.eq(counting:Mode(), GAMEPLAY, "and begins")
end)

T.test("with sandbox disabled, a map still starts as sv_gameplay_enabled says, and can leave Sandbox mode", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	T.eq(mode:Mode(), SANDBOX, "Sandbox mode")
	Expect(mode:Request(SANDBOX, BUTTON, START, SANDBOX_OFF, READY), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
		Gamemode.ALREADY_SANDBOX, "already there, not denied")
	Expect(mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_OFF, READY), Gamemode.START_LOAD_COUNTDOWN, Gamemode.NOTICE_NONE, nil,
		"out of Sandbox mode")
end)

T.test("the deny sound is the locked button's", function()
	T.eq(Gamemode.DENY_SOUND, "buttons/button10.wav", "HL2's deny")
end)

-- A map without an objective has no rounds until a game begins: then they
-- load (untimed, to the round limits) and it is a map with rounds.
T.test("a game begun on a map without rounds loads them and counts down, from any source", function()
	for _, source in ipairs({ BUTTON, CONSOLE, AI_WAR }) do
		local mode = Gamemode.New(NO_ROUNDS, DISABLED)
		local answer = mode:Request(GAMEPLAY, source, START, SANDBOX_ALLOWED, READY)
		T.eq(answer.action, Gamemode.START_LOAD_COUNTDOWN, "the countdown")
		T.eq(answer.loadRounds, true, "the rounds load")
		T.eq(answer.refusal, nil, "granted")
		T.eq(mode:Mode(), Gamemode.TRANSITION, "counting down")
		local cues = mode:Advance(START + Gamemode.COUNTDOWN)
		T.eq(cues[#cues].kind, Gamemode.CUE_BEGIN, "then Gameplay mode")
		local again = mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
		T.eq(again.loadRounds, nil, "loaded once")
	end
end)

T.test("Stop Game on a map whose rounds never loaded says why", function()
	local mode = Gamemode.New(NO_ROUNDS, DISABLED)
	Expect(mode:Request(SANDBOX, BUTTON, START, SANDBOX_ALLOWED, READY), Gamemode.STAY, Gamemode.NOTICE_REFUSED, Gamemode.NO_ROUNDS, "refused")
	T.eq(mode:Mode(), SANDBOX, "Sandbox mode")
end)

T.test("once loaded, the rounds stay: Stop Game returns to Sandbox mode as on a map with rounds", function()
	local mode = Gamemode.New(NO_ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	mode:Advance(START + Gamemode.COUNTDOWN)
	T.eq(mode:Request(SANDBOX, BUTTON, START + 30, SANDBOX_ALLOWED, READY).action, Gamemode.ENTER_SANDBOX, "Sandbox mode")
end)

-- Waiting for players: a game begins only once the mode's player
-- requirement is met (mp_waitingforplayers); until then the map waits in
-- Sandbox mode, and the countdown starts by itself when the players come.

T.test("asked for Gameplay mode without the players it needs, the map waits, then counts down once they come", function()
	for _, source in ipairs({ BUTTON, CONSOLE, AI_WAR }) do
		local mode = Gamemode.New(ROUNDS, DISABLED)
		Expect(mode:Request(GAMEPLAY, source, START, SANDBOX_ALLOWED, MISSING), Gamemode.WAIT, Gamemode.NOTICE_WAITING, nil,
			"waits, " .. source)
		T.eq(mode:Mode(), WAITING, "waiting, " .. source)
		T.eq(#mode:Advance(START + Gamemode.COUNTDOWN), 0, "no countdown while waiting, " .. source)
		T.eq(mode:TransitionEnd(), nil, "no end to show, " .. source)
		T.eq(mode:Players(MISSING, START + 20).action, Gamemode.STAY, "still missing, " .. source)
		local came = START + 30
		Expect(mode:Players(READY, came), Gamemode.START_LOAD_COUNTDOWN, Gamemode.NOTICE_NONE, nil, "they came, " .. source)
		T.eq(mode:TransitionEnd(), came + Gamemode.COUNTDOWN, "counting from their coming, " .. source)
		local cues = mode:Advance(came + Gamemode.COUNTDOWN)
		T.eq(cues[#cues].kind, Gamemode.CUE_BEGIN, "then Gameplay mode, " .. source)
		T.eq(mode:Players(MISSING, came + 60).action, Gamemode.STAY, "once begun, players leaving change nothing, " .. source)
		T.eq(mode:Mode(), GAMEPLAY, "still Gameplay mode, " .. source)
	end
end)

T.test("players coming outside a wait change nothing", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	T.eq(mode:Players(READY, START).action, Gamemode.STAY, "Sandbox mode")
	T.eq(mode:Mode(), SANDBOX, "still Sandbox mode")
end)

T.test("waiting, asking again says so, the AI war joins the wait, and Stop calls it off", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, MISSING)
	Expect(mode:Request(GAMEPLAY, BUTTON, START + 1, SANDBOX_ALLOWED, MISSING), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
		Gamemode.ALREADY_WAITING, "the button again")
	Expect(mode:Request(GAMEPLAY, AI_WAR, START + 2, SANDBOX_ALLOWED, MISSING), Gamemode.STAY, Gamemode.NOTICE_REQUEST_CHAT, nil,
		"the AI war")
	Expect(mode:Request(SANDBOX, BUTTON, START + 3, SANDBOX_ALLOWED, MISSING), Gamemode.STOP_WAITING, Gamemode.NOTICE_CALLED_OFF,
		nil, "Stop")
	T.eq(mode:Mode(), SANDBOX, "back in Sandbox mode")
	T.eq(mode:Players(READY, START + 4).action, Gamemode.STAY, "the wait is over")
end)

T.test("with sandbox disabled, a wait is not called off", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_OFF, MISSING)
	Expect(mode:Request(SANDBOX, BUTTON, START + 1, SANDBOX_OFF, MISSING), Gamemode.STAY, Gamemode.NOTICE_DENIED,
		Gamemode.SANDBOX_DISABLED, "denied")
	T.eq(mode:Mode(), WAITING, "still waiting")
end)

T.test("a game begun on a map without rounds loads them even while it waits", function()
	local mode = Gamemode.New(NO_ROUNDS, DISABLED)
	local answer = mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, MISSING)
	T.eq(answer.action, Gamemode.WAIT, "waits")
	T.eq(answer.loadRounds, true, "the rounds load")
end)

T.test("the wait leaves the setting as it was", function()
	T.eq(Gamemode.SETTING[WAITING], nil)
end)

T.test("a map loading in Gameplay mode without its players waits for them, then counts down as a request does", function()
	local mode = Gamemode.New(ROUNDS, ENABLED)
	T.eq(mode:Load(START, MISSING).action, Gamemode.WAIT, "waits")
	T.eq(mode:Mode(), WAITING, "waiting")
	T.eq(mode:Players(READY, START).action, Gamemode.START_LOAD_COUNTDOWN, "they came")
	T.eq(mode:Mode(), Gamemode.TRANSITION, "counting down")
	T.eq(mode:TransitionEnd(), START + Gamemode.COUNTDOWN, "a request's length")
end)

-- On a map change the players are still loading: the countdown is long
-- (LOAD_COUNTDOWN), cut to HURRIED_COUNTDOWN once those expected from the
-- previous map are in (Hurry).
T.test("the tuning is defined", function()
	T.defined(Gamemode.LOAD_COUNTDOWN, "LOAD_COUNTDOWN")
	T.defined(Gamemode.HURRIED_COUNTDOWN, "HURRIED_COUNTDOWN")
	T.defined(Gamemode.CLEANUP_AT, "CLEANUP_AT")
	T.defined(Gamemode.PREROUND_AT, "PREROUND_AT")
	T.defined(Gamemode.ANNOUNCE_AT, "ANNOUNCE_AT")
end)

T.test("a map loading in Gameplay mode counts down LOAD_COUNTDOWN seconds, then begins it", function()
	local mode = Gamemode.New(ROUNDS, ENABLED)
	T.eq(mode:Load(START, READY).action, Gamemode.START_LOAD_COUNTDOWN, "counts down, quietly")
	T.eq(mode:Mode(), Gamemode.TRANSITION, "counting down")
	local finish = START + Gamemode.LOAD_COUNTDOWN
	T.eq(mode:TransitionEnd(), finish, "its end")
	T.eq(#Kinds(mode:Advance(finish - 0.5), Gamemode.CUE_BEGIN), 0, "not before its end")
	local cues = mode:Advance(finish)
	T.eq(#Kinds(cues, Gamemode.CUE_BEGIN), 1, "begins at its end")
	T.eq(mode:Mode(), GAMEPLAY, "Gameplay mode")
end)

T.test("the load countdown counts every second, so the announcer's long lines are reached", function()
	local mode = Gamemode.New(ROUNDS, ENABLED)
	mode:Load(START, READY)
	local counts = Kinds(mode:Advance(START + Gamemode.LOAD_COUNTDOWN), Gamemode.CUE_COUNT)
	T.eq(#counts, Gamemode.LOAD_COUNTDOWN - 1, "one count a second")
	T.eq(counts[1].left, Gamemode.LOAD_COUNTDOWN - 1, "first count")
	T.eq(counts[#counts].left, 1, "last count")
end)

T.test("a map loads once: a second Load, or one outside Gameplay mode, changes nothing", function()
	local mode = Gamemode.New(ROUNDS, ENABLED)
	mode:Load(START, READY)
	T.eq(mode:Load(START + 1, READY).action, Gamemode.STAY, "loaded already")
	T.eq(mode:TransitionEnd(), START + Gamemode.LOAD_COUNTDOWN, "its end unmoved")
	local sandbox = Gamemode.New(ROUNDS, DISABLED)
	T.eq(sandbox:Load(START, READY).action, Gamemode.STAY, "Sandbox mode")
	T.eq(sandbox:Mode(), SANDBOX, "stays")
end)

T.test("once the expected players are in, the load countdown ends HURRIED_COUNTDOWN later, said at once", function()
	local mode = Gamemode.New(ROUNDS, ENABLED)
	mode:Load(START, READY)
	mode:Advance(START + 10)
	local at = START + 10.5
	T.eq(mode:Hurry(at), true, "hurried")
	T.eq(mode:TransitionEnd(), at + Gamemode.HURRIED_COUNTDOWN, "its new end")
	local now = Kinds(mode:Advance(at), Gamemode.CUE_COUNT)
	T.eq(#now, 1, "one count at once")
	T.eq(now[1].left, Gamemode.HURRIED_COUNTDOWN, "the time left")
	local rest = mode:Advance(at + Gamemode.HURRIED_COUNTDOWN)
	T.eq(#Kinds(rest, Gamemode.CUE_COUNT), Gamemode.HURRIED_COUNTDOWN - 1, "counts on from there")
	T.eq(#Kinds(rest, Gamemode.CUE_BEGIN), 1, "begins at the new end")
end)

T.test("a load countdown already within HURRIED_COUNTDOWN is not lengthened", function()
	local mode = Gamemode.New(ROUNDS, ENABLED)
	mode:Load(START, READY)
	local late = START + Gamemode.LOAD_COUNTDOWN - Gamemode.HURRIED_COUNTDOWN + 1
	mode:Advance(late)
	T.eq(mode:Hurry(late), false, "unchanged")
	T.eq(mode:TransitionEnd(), START + Gamemode.LOAD_COUNTDOWN, "its end")
end)

T.test("a requested countdown starts at the load's length and can be hurried", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	T.eq(mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY).action, Gamemode.START_LOAD_COUNTDOWN, "long countdown")
	T.eq(mode:TransitionEnd(), START + Gamemode.LOAD_COUNTDOWN, "request length")
	T.eq(mode:WaitsForExpectedPlayers(), false, "not waiting for the old map's players")
	T.eq(mode:Hurry(START + 10), true, "ready bots can hurry it")
	T.eq(mode:TransitionEnd(), START + 10 + Gamemode.HURRIED_COUNTDOWN, "hurried request")
	T.eq(Gamemode.New(ROUNDS, ENABLED):Hurry(START), false, "no countdown")
end)

-- The load countdown opens quietly, its players still loading: the
-- request's opening cues (the map's description, the matchmaking sting,
-- the announcer) come once they are in, or HURRIED_COUNTDOWN seconds before
-- its end, whichever is first, once.
T.test("the load countdown opens once its players are in, before the count it is cut to", function()
	local mode = Gamemode.New(ROUNDS, ENABLED)
	mode:Load(START, READY)
	T.eq(#Kinds(mode:Advance(START + 10), Gamemode.CUE_OPENING), 0, "not while they load")
	mode:Hurry(START + 10.5)
	local cues = mode:Advance(START + 10.5)
	T.eq(cues[1].kind, Gamemode.CUE_OPENING, "opens first")
	T.eq(cues[2].left, Gamemode.HURRIED_COUNTDOWN, "then the count")
	T.eq(#Kinds(mode:Advance(START + 10.5 + Gamemode.HURRIED_COUNTDOWN), Gamemode.CUE_OPENING), 0, "once")
end)

T.test("a load countdown never cut short opens HURRIED_COUNTDOWN seconds before its end", function()
	local mode = Gamemode.New(ROUNDS, ENABLED)
	mode:Load(START, READY)
	local at = START + Gamemode.LOAD_COUNTDOWN - Gamemode.HURRIED_COUNTDOWN
	T.eq(#Kinds(mode:Advance(at - 1), Gamemode.CUE_OPENING), 0, "not yet")
	T.eq(#Kinds(mode:Advance(at), Gamemode.CUE_OPENING), 1, "opens")
	T.eq(#Kinds(mode:Advance(START + Gamemode.LOAD_COUNTDOWN), Gamemode.CUE_OPENING), 0, "once")
end)

T.test("a requested countdown opens quietly until it is hurried", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED, READY)
	T.eq(#Kinds(mode:Advance(START), Gamemode.CUE_OPENING), 0, "quiet initially")
	mode:Hurry(START + 10)
	T.eq(#Kinds(mode:Advance(START + 10), Gamemode.CUE_OPENING), 1, "opens on readiness")
end)

T.finish()
