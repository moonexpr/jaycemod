-- The round and the match, on the server. The match is one coroutine, resumed
-- each Think: it reads top to bottom as the match goes, and waits where the
-- match waits. Whatever closes a round (a map's entity, the game being played,
-- a timer) calls RoundOutcome; that reaches the gamemode through its RoundWin
-- hook, and a gamemode answering with Declare ends the round the coroutine is
-- waiting on.
local CreateConVar, FCVAR_ARCHIVE, FCVAR_NOTIFY, HUD_PRINTCENTER, PrintMessage, SetGlobal2Int =
	CreateConVar, FCVAR_ARCHIVE, FCVAR_NOTIFY, HUD_PRINTCENTER, PrintMessage, SetGlobal2Int
local coroutine, debug, error, game, game_manager, game_timer, hook, ipairs, player, team =
	coroutine, debug, error, game, game_manager, game_timer, hook, ipairs, player, team
local ROUND_WAITING, ROUND_PREPARE, ROUND_ACTIVE, ROUND_OVER =
	ROUND_WAITING, ROUND_PREPARE, ROUND_ACTIVE, ROUND_OVER
local TEAM_RED, TEAM_BLUE, TF_TEAM_UNASSIGNED = TEAM_RED, TEAM_BLUE, TF_TEAM_UNASSIGNED
module("round_manager", package.seeall)

local PREPARE_TIME = 5
local ROUND_TIME = 300
local OVER_TIME = 8

local winlimit = CreateConVar("mp_winlimit", "3", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Rounds a team must win to take the match", 1)

local match
local declared
local playing -- whether a round is being played

-- A new phase: its clock, and none of the last one's. options: game_timer.Start's.
local function SetRound(state, duration, options)
	SetGlobal2Int("SandcastleRoundState", state)
	game_timer.StopAll()
	if duration then game_timer.Start(game_timer.ROUND, duration, options) end
	hook.Run("OnRoundStateChanged", state)
end

local function TeamsReady()
	return team.NumPlayers(TEAM_RED) > 0 and team.NumPlayers(TEAM_BLUE) > 0
end

-- The winner the games name, or what the gamemode declared.
local function Outcome()
	if declared ~= nil then return declared end
	for _, name in ipairs(game_manager.Active()) do
		local winner = game_manager.RunClass(name, "RoundWinner")
		if winner then return winner end
	end
end

local function Prepare()
	game.CleanUpMap()
	SetRound(ROUND_PREPARE, PREPARE_TIME)
	for _, ply in ipairs(player.GetAll()) do
		if team.Joinable(ply:Team()) then ply:Spawn() end
	end
	game_manager.RunActive("RoundPrepare")
	coroutine.wait(PREPARE_TIME)
end

-- The team that won, or nil when the time ran out.
local function Play()
	declared = nil
	-- its clock running out closes the round with nobody winning
	SetRound(ROUND_ACTIVE, ROUND_TIME, { outcome = {} })
	game_manager.RunActive("RoundStart")
	playing = true
	while game_timer.Running(game_timer.ROUND) do
		local winner = Outcome()
		if winner ~= nil then
			playing = false
			return winner
		end
		coroutine.yield()
	end
	playing = false
	return declared
end

-- Game state a map's entity may change. info: team, score, activator, event
-- (what it was for: "control_point_capture"), told to the games being played,
-- which may close the round for it, then to the TeamScored hook.
function AddTeamScore(info)
	team.AddScore(info.team, info.score)
	game_manager.RunActive("TeamScored", info)
	hook.Run("TeamScored", info)
end

-- Game state a map's entity may change. info: team, delta (seconds), activator,
-- event, told to the RoundTimeAdjusted hook. The round has one clock here, whatever the team.
function AdjustTime(info)
	if playing then game_timer.AddTime(game_timer.ROUND, info.delta) end
	hook.Run("RoundTimeAdjusted", info)
end

-- Whether this round took the match.
local function Finish(winner)
	SetRound(ROUND_OVER, OVER_TIME)
	if winner == TF_TEAM_UNASSIGNED then winner = nil end
	game_manager.RunActive("RoundEnd", winner)
	if winner == nil then
		PrintMessage(HUD_PRINTCENTER, "Stalemate")
		coroutine.wait(OVER_TIME)
		return false
	end
	AddTeamScore({ team = winner, score = 1, event = "round_win" })
	PrintMessage(HUD_PRINTCENTER, team.GetName(winner) .. " wins the round")
	coroutine.wait(OVER_TIME)
	return team.GetScore(winner) >= winlimit:GetInt()
end

local function PlayMatch()
	while true do
		while not TeamsReady() do coroutine.yield() end
		Prepare()
		local winner = Play()
		local bonus = (winner == nil or winner == TF_TEAM_UNASSIGNED) and game_manager.Tiebreaker()
		if bonus then
			game_manager.SetBonus(bonus)
			Prepare()
			winner = Play()
			game_manager.SetBonus(nil)
		end
		if Finish(winner) then
			game.LoadNextMap()
			return
		end
	end
end

-- The round is over; the gamemode's RoundWin decides what that means.
-- outcome: team (the winner; none, or TF_TEAM_UNASSIGNED, for a stalemate or
-- a tie), reason (the caller's: a WINREASON), forceMapReset, switchTeams.
function RoundOutcome(outcome)
	hook.Run("RoundWin", outcome.team or TF_TEAM_UNASSIGNED, outcome)
end

-- The answer to RoundWin that ends the round being played.
function Declare(winner)
	declared = winner
end

-- Each Think. active: whether the gamemode is running rounds.
function Think(active)
	if not active then
		if match then
			match = nil
			SetRound(ROUND_WAITING)
		end
		return
	end
	match = match or coroutine.create(PlayMatch)
	local ok, err = coroutine.resume(match)
	if not ok then
		local trace = debug.traceback(match, err)
		match = nil
		error(trace, 0)
	end
	if coroutine.status(match) == "dead" then match = nil end
end
