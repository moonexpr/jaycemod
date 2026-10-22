-- The Mode strategy games.gameplay.rounds declares, the control points mode
-- (CTFGameRules's TF_GAMETYPE_CP rules), and the objective port's contract.
local T = dofile("tests/harness.lua")
local FakeObjective = dofile("tests/fake_objective.lua")
local Rounds = T.require("games.gameplay.rounds")
local ControlPoints = T.require("foundation.rounds.control_points")
local Teams = T.require("games.gameplay.teams")

local RED, BLUE = Teams.RED, Teams.BLUE
local CP = ControlPoints.Mode

local SETTINGS = {
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

-- Stand-ins with the priorities the koth and payload modes declare.
local function Variant(name, priority)
	local mode = CP:Extend(name)
	mode.PRIORITY = priority
	return mode
end

local KOTH_PRIORITY, PAYLOAD_PRIORITY = 3, 2

T.test("the mode with the highest priority wins, as CTFGameRules::Activate picks the game type", function()
	local koth = Variant("koth", KOTH_PRIORITY)
	local payload = Variant("payload", PAYLOAD_PRIORITY)
	local round = Rounds.New(SETTINGS)
	T.eq(round:Mode(), Rounds.Mode, "no mode until an entity chooses one")
	T.eq(round:SetMode(CP), true, "control points")
	T.eq(round:SetMode(payload), true, "payload over control points")
	T.eq(round:SetMode(koth), true, "koth over payload")
	T.eq(round:Mode(), koth, "koth")
	local other = Rounds.New(SETTINGS)
	other:SetMode(koth)
	T.eq(other:SetMode(CP), false, "control points never replace koth")
	T.eq(other:Mode(), koth, "still koth")
	T.eq(other:SetMode(koth), false, "the same mode is no change")
end)

T.test("a cap that does not win the game plays Success to the cappers and Failure to the rest", function()
	local sounds = CP:CapSounds(BLUE, {
		wouldWinGame = false,
		scorePerRound = true,
	})
	T.eq(#sounds, 2, "one line per game team")
	T.eq(sounds[1].team, RED, "RED first, as the SDK loops from FIRST_GAME_TEAM")
	T.eq(sounds[1].sound, ControlPoints.FAILURE, "RED hears failure")
	T.eq(sounds[2].team, BLUE, "then BLU")
	T.eq(sounds[2].sound, ControlPoints.SUCCESS, "BLU hears success")
	T.eq(#CP:CapSounds(BLUE, {
		wouldWinGame = true,
		scorePerRound = true,
	}), 0, "the winning cap is silent")
	T.eq(#CP:CapSounds(BLUE, {
		wouldWinGame = false,
		scorePerRound = false,
	}), 0, "score per capture is silent")
end)

T.test("the control points mode", function()
	T.eq(CP.NAME, "control_points", "name")
	T.eq(CP.PRIORITY, 1, "priority")
	T.eq(CP.HUD, Rounds.HUD_CONTROL_POINTS, "the point HUD")
	T.eq(CP.CREATES_TIME_LIMIT_TIMER, true, "a time limit timer")
	T.eq(CP.ANNOUNCES_TIME_ADDED, true, "time added is announced")
	T.eq(CP:MayWinByPoints(RED, { timerMayExpire = false }), true, "owning every point wins at once")
end)

T.test("the base mode's defaults", function()
	local m = Rounds.Mode
	T.eq(m.NAME, "none", "name")
	T.eq(m.PRIORITY, 0, "priority")
	T.eq(m.HUD, Rounds.HUD_NONE, "no HUD")
	T.eq(m.CREATES_TIME_LIMIT_TIMER, true, "time limit timer")
	T.eq(m.ANNOUNCES_TIME_ADDED, true, "announces time added")
	T.eq(m:MayWinByPoints(RED, { timerMayExpire = true }), true, "may win")
	T.eq(#m:CapSounds(RED, {
		wouldWinGame = false,
		scorePerRound = true,
	}), 0, "no cap sounds")
	T.eq(next(m:RoundWinLines(RED, true, nil)), nil, "no win lines")
	T.eq(Rounds.HUD_NONE, 0, "HUD_NONE")
	T.eq(Rounds.HUD_CONTROL_POINTS, 1, "HUD_CONTROL_POINTS")
	T.eq(Rounds.HUD_KOTH, 2, "HUD_KOTH")
	T.eq(Rounds.HUD_PAYLOAD, 3, "HUD_PAYLOAD")
end)

T.test("Extend inherits every default and override, and names the variant", function()
	local gated = CP:Extend("gated")
	function gated:MayWinByPoints(team, q) return q.timerMayExpire end
	T.eq(gated.NAME, "gated", "named")
	T.eq(gated.HUD, Rounds.HUD_CONTROL_POINTS, "the parent's HUD")
	T.eq(#gated:CapSounds(BLUE, {
		wouldWinGame = false,
		scorePerRound = true,
	}), 2, "the parent's sounds")
	T.eq(gated:RoundWinLines(RED, true, nil) ~= nil, true, "the base's win lines")
	T.eq(CP.NAME, "control_points", "the parent keeps its name")

	local round = Rounds.New(SETTINGS)
	round:SetMode(gated)
	T.eq(round:MayWinByPoints(RED, { timerMayExpire = false }), false, "the round asks its mode")
	T.eq(round:MayWinByPoints(RED, { timerMayExpire = true }), true, "and the mode answers")
end)

T.test("the fake objective implements the port, and NO_OBJECTIVE answers for a map without one", function()
	local fake = FakeObjective.Objective()
	for _, name in ipairs(Rounds.OBJECTIVE_METHODS) do
		T.eq(type(fake[name]), "function", "fake " .. name)
	end
	local none = Rounds.NO_OBJECTIVE
	T.eq(none:PlayingMiniRounds(), false, "no mini-rounds")
	T.eq(none:NumPlayable(), 0, "none playable")
	T.eq(none:PlayAllRounds(), false, "no play-all")
	T.eq(none:RoundsRemaining(RED), 0, "none remaining")
	T.eq(none:ScorePerRound(), true, "score per round")
	T.eq(none.SuddenDeathWin, nil, "sudden death ends by SetWinningTeam")
end)

T.test("the round phases' listener order: timers, then capture, then logic", function()
	T.eq(Rounds.LISTEN_TIMERS < Rounds.LISTEN_CAPTURE, true, "timers first")
	T.eq(Rounds.LISTEN_CAPTURE < Rounds.LISTEN_LOGIC, true, "logic last")
	T.eq(Rounds.PHASE_SPAWN, "spawn", "spawn")
	T.eq(Rounds.PHASE_ACTIVATE, "activate", "activate")
	T.eq(Rounds.PHASE_ROUND_END, "round_end", "round end")
end)

-- Seams, read as text: what other features call on the rounds controller
-- (docs/pass4-koth-cp.md, section 2.4), and bindings that load nothing at top level.

local function Read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

local CONTROLLER_METHODS = {
	"BindProxy", "Proxy", "BindTimer", "TimerOf", "HudTimer", "SetActiveTimer", "CreateTimer", "TimerInput",
	"SetMode", "Mode", "AddRoundListener", "AddTimerHold", "TimerMayExpire", "MayWinByPoints", "SetObjective",
	"SetTeamClock", "TeamClock", "ActivateTeamClock",
	"State", "PointsMayBeCaptured", "InSetup", "InOvertime", "SetWinningTeam", "SetStalemate",
	"AddPlayedRound", "History", "SetFirstRoundPlayed",
	"CapSounds",
	"OnPlayerDeath", "Halt", "CleanUp", "BeginGame", "Halted", "RestartRound", "RespawnsDisabled", "SetRespawnsDisabled",
	"SetAdminRespawnWaveTime", "TeamRespawnWaveTime", "GetRespawnWaveMaxLength", "ProxyInput",
}

T.test("the rounds controller defines every method other features call", function()
	local source = T.RealmSource("rounds", "sv")
	for _, name in ipairs(CONTROLLER_METHODS) do
		T.eq(source:find("function Controller:" .. name .. "(", 1, true) ~= nil, true, name)
	end
end)

T.test("the rounds bindings load the feature on first use, never at file top level", function()
	local entities = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"
	for _, file in ipairs({ "ws_gamerules", "tf_gamerules", "team_round_timer", "game_round_win", "tf_logic_competitive" }) do
		local source = Read(entities .. file .. ".lua")
		T.eq(source:find('require("foundation.', 1, true), nil, file .. " requires no model")
		T.eq(source:find("\nlocal %w+ = WS%.Feature"), nil, file .. " loads nothing at top level")
	end
end)

T.test("the ws_gamerules binding keeps the gamerules surface as forwards", function()
	local source = Read("addons/sandcastle/gamemodes/sandcastle/entities/entities/ws_gamerules.lua")
	for _, name in ipairs({ "OnPlayerDeath", "Halt", "CleanUp", "BeginGame", "Halted", "RestartRound", "SetWinningTeam", "SetStalemate" }) do
		T.eq(source:find("function ENT:" .. name .. "(", 1, true) ~= nil, true, name)
	end
end)

-- TF2's gamerules are Sandcastle's, running rounds from the start.
T.test("tf_gamerules derive the surface from ws_gamerules and run rounds", function()
	local source = Read("addons/sandcastle/gamemodes/sandcastle/entities/entities/tf_gamerules.lua")
	T.eq(source:find('ENT.Base = "ws_gamerules"', 1, true) ~= nil, true, "base")
	T.eq(source:find("ENT.RunsRounds = true", 1, true) ~= nil, true, "runs rounds")
end)

-- A mode's player requirement (PLAYERS_NEEDED): a game begins once it is
-- met (games.system.gamemode). counts: each team's players and NPCs, and the
-- players on neither (teams are chosen once the game begins).

local function Counts(r, b, free) return { [RED] = r, [BLUE] = b, free = free or 0 } end

T.test("the base mode needs nobody", function()
	local have, need = Rounds.PlayersNeeded(Rounds.Mode.PLAYERS_NEEDED, Counts(0, 0))
	T.eq(have >= need, true, "met with nobody there")
end)

T.test("a requirement counts both teams together, or one team alone, and the teamless toward either", function()
	local both, red = { count = 3 }, { team = RED, count = 3 }
	local function Have(needed, counts) return (Rounds.PlayersNeeded(needed, counts)) end
	T.eq(Have(both, Counts(1, 1)), 2, "both teams")
	T.eq(Have(red, Counts(1, 5)), 1, "RED alone")
	T.eq(Have(both, Counts(1, 1, 2)), 4, "the teamless, with both")
	T.eq(Have(red, Counts(1, 5, 2)), 3, "the teamless, with RED")
	T.eq(select(2, Rounds.PlayersNeeded(red, Counts(0, 0))), 3, "what it needs")
end)

T.finish()
