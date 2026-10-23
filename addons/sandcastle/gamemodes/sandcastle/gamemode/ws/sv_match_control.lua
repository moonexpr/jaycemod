-- The commands behind Utilities > Admin > Match Control (ws/cl_match_control.lua),
-- each checked against its privilege (games.system.permissions):
-- - round: mp_round_suddendeath, mp_round_restart (a stalemate, or back to Pregame), and
--   mp_round_reward_money, paid to every player of the round's winners.
--   WSRoundRewards(winner) lets a server add its own rewards.
-- - match: mp_match_forcewin red|blue|sudden (sudden: a sudden death whose
--   winner wins the match). Begin and Stop Game are ws/sh_gameplay.lua's.
-- - tamper (refused to every player while mp_tampering_enabled is 0): the
--   payload carts (mp_cart_advance, mp_cart_retract), the round clock
--   (mp_round_timer_add, mp_round_timer_pause), and respawns
--   (mp_respawn_all, mp_respawn_maptimes).
local Permissions = system.permissions

local REWARD = CreateConVar("mp_round_reward_money", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
	"Money paid to every player on the team that wins a round", 0, 100000)

local function Reply(ply, text)
	if IsValid(ply) then ply:ChatPrint(text) else print(text) end
end

-- A console command for holders of privilege; run(args) answers true, or
-- false and why.
local function Command(name, privilege, help, run)
	concommand.Add(name, function(ply, _, args)
		if not WS.Can(ply, privilege) then return Reply(ply, name .. ": you may not do that") end
		local ok, why = run(args)
		if ok then
			print("[Sandcastle] " .. (IsValid(ply) and ply:Nick() or "Console") .. " ran " .. name .. " " .. table.concat(args, " "))
		else
			Reply(ply, name .. ": " .. why)
		end
	end, nil, help)
end

local NO_ROUNDS = "this map has no rounds"

local function RoundsFeature()
	return WS.Active() and WS.Feature("rounds") or nil
end

Command("mp_round_suddendeath", Permissions.ROUND, "Send the running round to sudden death", function()
	local rounds = RoundsFeature()
	if not rounds then return false, NO_ROUNDS end
	return rounds:SuddenDeathNow(false)
end)

Command("mp_round_restart", Permissions.ROUND, "Restart the round: one with players ends as a stalemate first, else back to Pregame silently; money and weapons are kept", function()
	local rounds = RoundsFeature()
	if not rounds then return false, NO_ROUNDS end
	rounds:RestartRound()
	return true
end)

local MATCH_TARGETS = {
	red = WS.TEAM_RED,
	blue = WS.TEAM_BLUE,
	blu = WS.TEAM_BLUE,
}

Command("mp_match_forcewin", Permissions.MATCH,
	"End the match now: mp_match_forcewin red|blue, or sudden for a sudden death whose winner wins the match",
	function(args)
		local rounds = RoundsFeature()
		if not rounds then return false, NO_ROUNDS end
		local target = (args[1] or ""):lower()
		if target == "sudden" then return rounds:SuddenDeathNow(true) end
		local team = MATCH_TARGETS[target]
		if not team then return false, "red, blue or sudden" end
		return rounds:ForceMatchWin(team)
	end)

-- Round rewards: the money setting, then whatever a server adds.
hook.Add("WSRoundWin", "ws_match_control", function(winner)
	if winner ~= WS.TEAM_RED and winner ~= WS.TEAM_BLUE then return end
	local amount = REWARD:GetInt()
	if amount > 0 then
		for _, ply in ipairs(team.GetPlayers(winner)) do WS.GrantMoney(ply, amount) end
	end
	hook.Run("WSRoundRewards", winner)
end)

-- Tampering --------------------------------------------------------------------------

local function Editors()
	return WS.Feature("editors")
end

local function Carts(method)
	return function()
		local watchers = ents.FindByClass("team_train_watcher")
		if #watchers == 0 then return false, "this map has no payload cart" end
		for _, watcher in ipairs(watchers) do Editors()[method](Editors(), watcher) end
		return true
	end
end

Command("mp_cart_advance", Permissions.TAMPER, "Advance every payload cart to its next checkpoint", Carts("AdvanceCart"))
Command("mp_cart_retract", Permissions.TAMPER, "Retract every payload cart to its previous checkpoint", Carts("RetractCart"))

Command("mp_round_timer_add", Permissions.TAMPER, "Add seconds to the round clock (negative takes them away)", function(args)
	local seconds = tonumber(args[1] or "")
	if not seconds then return false, "give a number of seconds" end
	local editors = Editors()
	return editors:SetTimeLeft(editors:TimeLeft() + seconds)
end)

Command("mp_round_timer_pause", Permissions.TAMPER, "Pause the round clock, or resume it", function()
	local editors = Editors()
	return editors:SetPaused(not editors:Paused())
end)

Command("mp_respawn_all", Permissions.TAMPER, "Respawn every dead player now", function()
	local due = {}
	for _, ply in player.Iterator() do
		if not ply:Alive() and WS.TeamOf(ply) ~= WS.TEAM_UNASSIGNED and WS.TeamOf(ply) ~= WS.TEAM_SPECTATOR then due[#due + 1] = ply end
	end
	WS.Respawn(due)
	return true
end)

Command("mp_respawn_maptimes", Permissions.TAMPER, "Go back to the map's own respawn wave times", function()
	return Editors():UseMapRespawnTimes()
end)
