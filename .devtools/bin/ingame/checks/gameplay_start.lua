-- sv_gameplay_enabled 1, set as an admin would in the server console, runs
-- the transition (games.system.gamemode): the countdown, then Begin, which
-- unassigns everyone and restarts the rounds; with bots on both teams the
-- rounds go through the pre-round into a running round.
-- args: { red = n, blue = n } bots per team (default 2 each).
local Tests = WS_TESTS
local Gamemode = WS.require("games.system.gamemode")
local S = WS.STATE
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local DEFAULT_TEAM_SIZE = 2
local TRANSITION_START_TIMEOUT = 3
local TRANSITION_SLACK = 5 -- seconds past the countdown for Begin
local RUNNING_TIMEOUT = 30
local MODE_NAMES = {
	[Gamemode.SANDBOX] = "SANDBOX",
	[Gamemode.TRANSITION] = "TRANSITION",
	[Gamemode.GAMEPLAY] = "GAMEPLAY",
}

return function(t)
	local gamemode = t:Feature("gamemode")
	if not gamemode then return t:Skip("the gamemode feature is not loaded (a map without rounds)") end
	local function Mode() return gamemode.mode:Mode() end
	t:Check("starts in Sandbox mode", Mode() == Gamemode.SANDBOX, MODE_NAMES[Mode()])

	local redSize, blueSize = t.args.red or DEFAULT_TEAM_SIZE, t.args.blue or DEFAULT_TEAM_SIZE
	local bots = t:Bots(redSize + blueSize)
	RunConsoleCommand("sv_gameplay_enabled", "1")
	local inTransition = t:WaitFor(TRANSITION_START_TIMEOUT, function() return Mode() == Gamemode.TRANSITION end)
	t:Check("sv_gameplay_enabled 1 starts the transition", inTransition ~= nil, MODE_NAMES[Mode()])
	local began, took = t:WaitFor(Gamemode.COUNTDOWN + TRANSITION_SLACK, function() return Mode() == Gamemode.GAMEPLAY end)
	t:Check("the countdown ends in Gameplay mode", began ~= nil,
		string.format("%s after %.1f s (countdown %d s)", MODE_NAMES[Mode()], took, Gamemode.COUNTDOWN))
	t:Check("Gameplay mode unhalts the rounds", not WS.GameplayStopped(), tostring(WS.GameplayStopped()))

	local unassigned = 0
	for _, bot in ipairs(bots) do
		if bot:Team() == WS.TEAM_UNASSIGNED then unassigned = unassigned + 1 end
	end
	t:Check("Begin unassigns everyone", unassigned == #bots, unassigned .. " of " .. #bots .. " bots unassigned")

	local red, blue = {}, {}
	for i, bot in ipairs(bots) do
		if i <= redSize then red[#red + 1] = bot else blue[#blue + 1] = bot end
	end
	t:Join(red, RED)
	t:Join(blue, BLUE)

	local states, last = {}, nil
	local running = t:WaitFor(RUNNING_TIMEOUT, function()
		local state = WS.State()
		if state ~= last then
			states[#states + 1] = Tests.StateName(state)
			last = state
		end
		return state == S.RND_RUNNING
	end)
	t:Info("states_seen", states)
	t:Info("in_setup", WS.InSetup())
	t:Check("the rounds reach RND_RUNNING", running ~= nil, table.concat(states, " > "))
end
