-- Help Other Team (decision Q6, docs/spawn-menu-design.md): the handicap
-- (games.gameplay.handicap) a passed support vote grants, the AI capabilities it
-- carries (games.gameplay.capabilities), and the shorter respawn waves the
-- Round gives a helped team (Round:SetWaveScale).
local T = dofile("tests/harness.lua")
local Handicap = gameplay.handicap
local Capabilities = gameplay.capabilities
local Rounds = gameplay.rounds
local State = T.require("games.gameplay.rounds.state")
local Teams = gameplay.teams
local Transaction = transaction
local FakeObjective = dofile("tests/fake_objective.lua")

local RED, BLUE = Teams.RED, Teams.BLUE

T.test("a capability set holds what it was given, and is a new value each time", function()
	local none = Capabilities.None()
	local ambush = none:With(Capabilities.AMBUSH)
	T.eq(none:Has(Capabilities.AMBUSH), false, "none has none")
	T.eq(ambush:Has(Capabilities.AMBUSH), true, "given")
	T.eq(none:Has(Capabilities.AMBUSH), false, "the old value is unchanged")
end)

T.test("an unknown capability is our bug, not a player's refusal", function()
	local ok, err = pcall(Capabilities.None().With, Capabilities.None(), "teleport")
	T.eq(ok, false, "refused")
	T.eq(Transaction.IsRefusal(err, {}), false, "not a refusal a player gets")
end)

T.test("a new handicap helps nobody", function()
	local h = Handicap.New()
	T.eq(h:Supported(), Teams.UNASSIGNED, "nobody")
	T.eq(h:WaveScale(RED), Handicap.NO_SCALE, "red waits as usual")
	T.eq(h:Capabilities(RED):Has(Capabilities.AMBUSH), false, "no ambush")
end)

T.test("a team granted the handicap waits less and may ambush; the other does not", function()
	local h = Handicap.New():Grant(BLUE)
	T.eq(h:Supported(), BLUE, "blue")
	T.eq(h:WaveScale(BLUE), Handicap.WAVE_SCALE, "blue's waves shortened")
	T.eq(Handicap.WAVE_SCALE < Handicap.NO_SCALE, true, "shortened, not lengthened")
	T.eq(h:WaveScale(RED), Handicap.NO_SCALE, "red's as usual")
	T.eq(h:Capabilities(BLUE):Has(Capabilities.AMBUSH), true, "blue may ambush")
	T.eq(h:Capabilities(RED):Has(Capabilities.AMBUSH), false, "red may not")
end)

T.test("a team already helped is refused", function()
	local ok, err = pcall(Handicap.New():Grant(BLUE).Grant, Handicap.New():Grant(BLUE), BLUE)
	T.eq(ok, false, "refused")
	T.eq(err.kind, Handicap.ALREADY_SUPPORTED, "already supported")
end)

T.test("granting returns a new value; the one granted from is unchanged", function()
	local h = Handicap.New()
	h:Grant(RED)
	T.eq(h:Supported(), Teams.UNASSIGNED, "unchanged")
end)

T.test("the war holds each team's capabilities, none until set", function()
	local AiWar = T.require("features.aiwar.model")
	local war = AiWar.War.New()
	T.eq(war:Capabilities(BLUE):Has(Capabilities.AMBUSH), false, "none to begin with")
	war:SetCapabilities(BLUE, Handicap.New():Grant(BLUE):Capabilities(BLUE))
	T.eq(war:Capabilities(BLUE):Has(Capabilities.AMBUSH), true, "blue's, as granted")
	T.eq(war:Capabilities(RED):Has(Capabilities.AMBUSH), false, "red's untouched")
end)

-- The Round's wave scale ----------------------------------------------------------

local T0 = 100

local function Settings()
	return {
		respawnWaveTime = 10,
		bonusRoundTime = 15,
		enableRoundWaitTime = 1,
		stalemateEnable = false,
		stalemateTimelimit = 240,
		winlimit = 0,
		maxrounds = 0,
		timelimit = 0,
		matchEndAtTimelimit = false,
		chattime = 10,
		mapResetTime = 0,
	}
end

local function World()
	return {
		havePlayers = true,
		teams = {
			[RED] = {
				players = 1,
				alive = 1,
			},
			[BLUE] = {
				players = 1,
				alive = 1,
			},
		},
		scores = {
			[RED] = 0,
			[BLUE] = 0,
		},
		timerMayExpire = true,
		mapHasActiveTimer = true,
		objective = FakeObjective.Objective(),
	}
end

local function Running()
	local round = Rounds.New(Settings())
	round:Think(T0, World())
	round:Think(T0 + 1 + Rounds.PREROUND_SECONDS, World())
	T.eq(round:State(), State.RND_RUNNING, "running")
	return round
end

T.test("a scaled team's respawn wave is the scale's share of what it would have been", function()
	local round = Running()
	local before = round:WaveMaxLength(BLUE, 1, true)
	round:SetWaveScale(BLUE, Handicap.WAVE_SCALE)
	T.near(round:WaveMaxLength(BLUE, 1, true), before * Handicap.WAVE_SCALE, 1e-9, "blue's shortened")
	T.near(round:WaveMaxLength(RED, 1, true), before, 1e-9, "red's as it was")
end)

T.test("setup's quick waves stay as they are", function()
	local round = Rounds.New(Settings())
	round:Think(T0, World())
	round:SetWaveScale(BLUE, Handicap.WAVE_SCALE)
	T.eq(round:WaveMaxLength(BLUE, 1, true), round:WaveMaxLength(RED, 1, true), "the pre-round's are equal")
end)

T.finish()
