-- Part of the rounds controller (sv.lua): TF2's console commands that end
-- or restart the round (teamplayroundbased_gamerules.cpp). mp_forcewin
-- ends it now; mp_restartround, mp_restartgame and mp_restartgame_immediate
-- ask a restart, which the rounds read once a second (RestartAsked, in the
-- world they think with) and set back to 0 once it is due (sv_effects.lua's
-- restart_seconds).
local Controller, Active, ConVarOrCreate = ...
local Rounds = gameplay.rounds

local S = WS.STATE
local UNASSIGNED = WS.TEAM_UNASSIGNED

local restartround = ConVarOrCreate("mp_restartround", "0", 0, "If non-zero, the current round will restart in the specified number of seconds")
local restartgame = ConVarOrCreate("mp_restartgame", "0", 0, "If non-zero, game will restart in the specified number of seconds")
local restartgameImmediate = ConVarOrCreate("mp_restartgame_immediate", "0", 0, "If non-zero, game will restart immediately")

local function RestartAsked()
	return Rounds.RestartRequest(restartround:GetInt(), restartgame:GetInt(), restartgameImmediate:GetBool())
end

-- mp_forcewin [team#] (TF2's): the team wins the round as if it had
-- captured every point (a win that ends the match is the match win), team 0
-- ends it a stalemate, and with no team the first player's team wins.
-- Sandcastle's own: the teams' names, and sudden for the running round's
-- sudden death, called by the Administrator. Admins only, as Match Control.
local FORCE_WIN_OPTIONS = { "red", "blue", "sudden", tostring(UNASSIGNED) }

local function FirstPlayerTeam()
	local first = Entity(1)
	if IsValid(first) and first:IsPlayer() then return WS.TeamOf(first) end
	return nil
end

concommand.Add("mp_forcewin", function(ply, _, args)
	local function Reply(text)
		if IsValid(ply) then ply:ChatPrint(text) else print(text) end
	end
	if not WS.Can(ply, system.permissions.MATCH) then return Reply("mp_forcewin: you may not force a win") end
	local target, why = Rounds.ForceWinTarget(args, FirstPlayerTeam())
	if target == nil then return Reply(why) end
	if not Active() then return Reply("mp_forcewin: this map has no rounds") end
	if target == Rounds.FORCE_SUDDEN_DEATH then
		if Controller.round:State() ~= S.RND_RUNNING then return Reply("mp_forcewin: no round is running") end
		Controller:Apply(Controller.round:SuddenDeath(CurTime(), Rounds.STALEMATE.ADMIN))
		return
	end
	Controller:Apply(Controller.round:ForceWin(CurTime(), target, Controller.objective))
end, function(cmd)
	local options = {}
	for i, option in ipairs(FORCE_WIN_OPTIONS) do options[i] = cmd .. " " .. option end
	return options
end, "Force the round's end: mp_forcewin [2 red | 3 blue | 0 stalemate | sudden]; the first player's team with none; admins only")

return RestartAsked
