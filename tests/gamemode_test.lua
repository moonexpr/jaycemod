-- foundation.gamemode: the gamemode's own mode, Sandbox or Gameplay, and the
-- countdown between them, driven through whole scenarios with injected time.
local T = dofile("tests/harness.lua")
local Gamemode = T.require("foundation.gamemode")

local ROUNDS, NO_ROUNDS = true, false
local ENABLED, DISABLED = true, false -- sv_gameplay_enabled at map load
local SANDBOX_ALLOWED, SANDBOX_OFF = false, true -- sv_gameplay_disable_sandbox
local START = 100

local SANDBOX, GAMEPLAY = Gamemode.SANDBOX, Gamemode.GAMEPLAY
local BUTTON, CONSOLE, AI_WAR = Gamemode.SOURCE_BUTTON, Gamemode.SOURCE_CONSOLE, Gamemode.SOURCE_AI_WAR

-- The cues from START until the transition ends, each with the second it falls on.
local function RunCountdown(mode)
	local seen = {}
	for second = 1, Gamemode.ADMIN_LINE_AT do
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
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED)
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
	T.eq(#Gamemode.New(ROUNDS, ENABLED):Advance(START + Gamemode.ADMIN_LINE_AT), 0, "no countdown at load")
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
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED)
	T.eq(mode:SettingWants(true), GAMEPLAY, "during the transition, set to 1")
	T.eq(mode:SettingWants(false), SANDBOX, "during the transition, set to 0")
	RunCountdown(mode)
	T.eq(mode:SettingWants(true), nil, "Gameplay mode, set to 1: our own write")
	T.eq(mode:SettingWants(false), SANDBOX, "Gameplay mode, set to 0")
end)

T.test("the button in Sandbox mode starts the transition, which counts down and begins Gameplay mode", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	Expect(mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED), Gamemode.START_TRANSITION, Gamemode.NOTICE_NONE, nil,
		"the transition's own cues tell it")
	T.eq(mode:Mode(), Gamemode.TRANSITION, "counting down")
	local cues = RunCountdown(mode)
	local counts = Kinds(cues, Gamemode.CUE_COUNT)
	T.eq(#counts, Gamemode.COUNTDOWN, "one count a second")
	T.eq(counts[1].left, Gamemode.COUNTDOWN, "first count")
	T.eq(counts[1].second, 1, "a second in")
	T.eq(counts[Gamemode.COUNTDOWN].left, 1, "last count")
	for _, count in ipairs(counts) do
		T.eq(count.spoken, count.left <= Gamemode.SPOKEN_COUNT, "spoken at " .. count.left)
	end
	local admin = Kinds(cues, Gamemode.CUE_ADMIN_LINE)
	T.eq(#admin, 1, "one Administrator line")
	T.eq(admin[1].second, Gamemode.ADMIN_LINE_AT, "Administrator line's time")
	local begin = Kinds(cues, Gamemode.CUE_BEGIN)
	T.eq(#begin, 1, "one begin")
	T.eq(cues[#cues], begin[1], "begin comes last")
	T.eq(mode:Mode(), GAMEPLAY, "in Gameplay mode")
	T.eq(#mode:Advance(START + Gamemode.ADMIN_LINE_AT + 5), 0, "nothing after it began")
end)

T.test("the console's sv_gameplay_enabled 1 is a request like the button", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	Expect(mode:Request(GAMEPLAY, CONSOLE, START, SANDBOX_ALLOWED), Gamemode.START_TRANSITION, Gamemode.NOTICE_NONE, nil,
		"from Sandbox mode")
	RunCountdown(mode)
	T.eq(mode:Mode(), GAMEPLAY, "in Gameplay mode")
end)

T.test("a late tick catches up on every cue it missed, in order", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED)
	T.eq(#mode:Advance(START + 0.5), 0, "nothing before the first second")
	local cues = mode:Advance(START + Gamemode.ADMIN_LINE_AT + 3)
	T.eq(#Kinds(cues, Gamemode.CUE_COUNT), Gamemode.COUNTDOWN, "every count")
	T.eq(cues[1].left, Gamemode.COUNTDOWN, "counts from the top")
	T.eq(cues[#cues].kind, Gamemode.CUE_BEGIN, "then begins")
	T.eq(mode:Mode(), GAMEPLAY, "in Gameplay mode")
end)

T.test("AI war in Sandbox mode starts the transition and leaves its details in the chat", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	Expect(mode:Request(GAMEPLAY, AI_WAR, START, SANDBOX_ALLOWED), Gamemode.START_TRANSITION,
		Gamemode.NOTICE_REQUEST_CHAT, nil, "chat, no announcement")
	T.eq(mode:Mode(), Gamemode.TRANSITION, "counting down")
end)

T.test("AI war during the transition joins it without restarting the countdown", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED)
	mode:Advance(START + 4)
	Expect(mode:Request(GAMEPLAY, AI_WAR, START + 4, SANDBOX_ALLOWED), Gamemode.STAY, Gamemode.NOTICE_REQUEST_CHAT, nil,
		"already under way")
	local cues = mode:Advance(START + 5)
	T.eq(cues[1].left, Gamemode.COUNTDOWN - 4, "the countdown goes on")
end)

T.test("AI war in Gameplay mode is announced", function()
	local mode = InGameplay()
	Expect(mode:Request(GAMEPLAY, AI_WAR, START + 60, SANDBOX_ALLOWED), Gamemode.STAY,
		Gamemode.NOTICE_REQUEST_ANNOUNCEMENT, nil, "announcement")
	T.eq(mode:Mode(), GAMEPLAY, "still in Gameplay mode")
end)

T.test("Stop during the transition calls it off and stays in Sandbox mode", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED)
	mode:Advance(START + 3)
	Expect(mode:Request(SANDBOX, BUTTON, START + 3, SANDBOX_ALLOWED), Gamemode.CANCEL_TRANSITION,
		Gamemode.NOTICE_CALLED_OFF, nil, "called off")
	T.eq(mode:Mode(), SANDBOX, "Sandbox mode")
	T.eq(#mode:Advance(START + Gamemode.ADMIN_LINE_AT + 1), 0, "no cues after it was called off")
	T.eq(mode:Mode(), SANDBOX, "never began")
end)

T.test("the transition ends when Gameplay mode begins; outside it there is no end to show", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	T.eq(mode:TransitionEnd(), nil, "Sandbox mode")
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED)
	T.eq(mode:TransitionEnd(), START + Gamemode.ADMIN_LINE_AT, "counting down")
	mode:Advance(START + 4)
	T.eq(mode:TransitionEnd(), START + Gamemode.ADMIN_LINE_AT, "unmoved by the ticks")
	local begin = Kinds(mode:Advance(START + Gamemode.ADMIN_LINE_AT), Gamemode.CUE_BEGIN)
	T.eq(#begin, 1, "begins at that end")
	T.eq(mode:TransitionEnd(), nil, "Gameplay mode")
end)

T.test("a called-off transition has no end to show", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED)
	mode:Request(SANDBOX, BUTTON, START + 3, SANDBOX_ALLOWED)
	T.eq(mode:TransitionEnd(), nil, "called off")
	T.eq(Gamemode.New(ROUNDS, ENABLED):TransitionEnd(), nil, "Gameplay mode at load")
end)

T.test("a new transition after one was called off counts from its own start", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED)
	mode:Request(SANDBOX, BUTTON, START + 6, SANDBOX_ALLOWED)
	mode:Request(GAMEPLAY, BUTTON, START + 20, SANDBOX_ALLOWED)
	local cues = mode:Advance(START + 21)
	T.eq(#cues, 1, "one cue")
	T.eq(cues[1].left, Gamemode.COUNTDOWN, "from the top")
end)

T.test("Stop in Gameplay mode, or the console's sv_gameplay_enabled 0, enters Sandbox mode with its notice", function()
	for _, source in ipairs({ BUTTON, CONSOLE }) do
		local mode = InGameplay()
		Expect(mode:Request(SANDBOX, source, START + 60, SANDBOX_ALLOWED), Gamemode.ENTER_SANDBOX, Gamemode.NOTICE_SANDBOX,
			nil, source)
		T.eq(mode:Mode(), SANDBOX, "Sandbox mode, from " .. source)
	end
end)

T.test("the button in Gameplay mode or during the transition changes nothing and says why", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_ALLOWED)
	Expect(mode:Request(GAMEPLAY, BUTTON, START + 2, SANDBOX_ALLOWED), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
		Gamemode.ALREADY_COUNTING, "during the transition")
	RunCountdown(mode)
	Expect(mode:Request(GAMEPLAY, BUTTON, START + 60, SANDBOX_ALLOWED), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
		Gamemode.ALREADY_GAMEPLAY, "in Gameplay mode")
	T.eq(mode:Mode(), GAMEPLAY, "still in Gameplay mode")
end)

T.test("Stop in Sandbox mode changes nothing and says why", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	Expect(mode:Request(SANDBOX, BUTTON, START, SANDBOX_ALLOWED), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
		Gamemode.ALREADY_SANDBOX, "already")
end)

T.test("with sandbox disabled, no request enters Sandbox mode, and the requester is denied", function()
	for _, source in ipairs({ BUTTON, CONSOLE }) do
		local mode = InGameplay()
		Expect(mode:Request(SANDBOX, source, START + 60, SANDBOX_OFF), Gamemode.STAY, Gamemode.NOTICE_DENIED,
			Gamemode.SANDBOX_DISABLED, "from Gameplay mode, " .. source)
		T.eq(mode:Mode(), GAMEPLAY, "still in Gameplay mode, " .. source)
	end
	local counting = Gamemode.New(ROUNDS, DISABLED)
	counting:Request(GAMEPLAY, BUTTON, START, SANDBOX_OFF)
	Expect(counting:Request(SANDBOX, BUTTON, START + 3, SANDBOX_OFF), Gamemode.STAY, Gamemode.NOTICE_DENIED,
		Gamemode.SANDBOX_DISABLED, "during the transition")
	T.eq(#Kinds(counting:Advance(START + Gamemode.ADMIN_LINE_AT), Gamemode.CUE_BEGIN), 1, "the countdown goes on")
	T.eq(counting:Mode(), GAMEPLAY, "and begins")
end)

T.test("with sandbox disabled, a map still starts as sv_gameplay_enabled says, and can leave Sandbox mode", function()
	local mode = Gamemode.New(ROUNDS, DISABLED)
	T.eq(mode:Mode(), SANDBOX, "Sandbox mode")
	Expect(mode:Request(SANDBOX, BUTTON, START, SANDBOX_OFF), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
		Gamemode.ALREADY_SANDBOX, "already there, not denied")
	Expect(mode:Request(GAMEPLAY, BUTTON, START, SANDBOX_OFF), Gamemode.START_TRANSITION, Gamemode.NOTICE_NONE, nil,
		"out of Sandbox mode")
end)

T.test("the deny sound is the locked button's", function()
	T.eq(Gamemode.DENY_SOUND, "buttons/button10.wav", "HL2's deny")
end)

T.test("a map without rounds stays in Sandbox mode and says why, except to the AI war", function()
	local mode = Gamemode.New(NO_ROUNDS, DISABLED)
	for _, request in ipairs({
		{
			want = GAMEPLAY,
			source = BUTTON,
		},
		{
			want = GAMEPLAY,
			source = CONSOLE,
		},
		{
			want = SANDBOX,
			source = BUTTON,
		},
	}) do
		Expect(mode:Request(request.want, request.source, START, SANDBOX_ALLOWED), Gamemode.STAY, Gamemode.NOTICE_REFUSED,
			Gamemode.NO_ROUNDS, request.source)
	end
	Expect(mode:Request(GAMEPLAY, AI_WAR, START, SANDBOX_ALLOWED), Gamemode.STAY, Gamemode.NOTICE_NONE, Gamemode.NO_ROUNDS,
		"the war goes on without rounds")
	T.eq(mode:Mode(), SANDBOX, "Sandbox mode")
	T.eq(#mode:Advance(START + Gamemode.ADMIN_LINE_AT), 0, "no countdown")
end)

T.finish()
