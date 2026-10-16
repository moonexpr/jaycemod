-- The scoreboard player menu's requests (ws/sh_players_menu.lua). Reports
-- go to foundation.reports; the one that reaches the count runs
-- WSReportsReached(target, reason), which starts the vote to kick them.
-- Money a player gives moves through WS.TransferMoney. Kicks, bans and
-- grants need the players privilege. Every answer goes back to the player
-- who asked as players_menu_said.
local Reports = WS.require("foundation.reports")
local Economy = WS.require("foundation.economy")
local Permissions = WS.require("foundation.permissions")
local Refusal = WS.require("foundation.refusal")
local E = WS.Events

local book = Reports.New()

local REFUSED = {}
for kind in pairs(Reports.PLAYER) do REFUSED[kind] = true end
for kind in pairs(Economy.PLAYER) do REFUSED[kind] = true end

local function Say(ply, text, refused)
	E.Fire("players_menu_said", {
		text = text,
		refused = refused,
	}, ply)
end

local function Money(amount)
	return Economy.Format(amount)
end

-- The target a request names, or nil after telling the sender they are gone.
local function Target(ply, target)
	if IsValid(target) and target:IsPlayer() then return target end
	Say(ply, "That player has left.", true)
end

-- Runs fn; a refusal that is the player's mistake is told to them, anything
-- else, our bug, is rethrown. Whether fn ran through.
local function Try(ply, fn)
	local ok, err = pcall(fn)
	if not ok then Say(ply, Refusal.Explain(err, REFUSED), true) end
	return ok
end

E.Listen("player_report", "ws_players_menu", function(fields, ply)
	local target = Target(ply, fields.target)
	if not target then return end
	local reason = Reports.REASONS[fields.reason + 1]
	local players, configured = player.GetCount(), GetConVar("mp_reports_kick_count"):GetInt()
	local reached
	if not Try(ply, function() reached = Reports.File(book, ply, target, reason, players, configured) end) then return end
	if reached then
		Say(ply, "Report sent. Enough players reported " .. target:Nick() .. ": a vote to kick them starts.", false)
		hook.Run("WSReportsReached", target, reached)
		return
	end
	Say(ply, "Report sent. A vote to kick " .. target:Nick() .. " starts if "
		.. Reports.Needed(players, configured) .. " players report them.", false)
end)

hook.Add("PlayerDisconnected", "ws_players_menu", function(ply) Reports.Forget(book, ply) end)

E.Listen("money_transfer", "ws_players_menu", function(fields, ply)
	local target = Target(ply, fields.target)
	if not target then return end
	if not Try(ply, function() WS.TransferMoney(ply, target, fields.amount) end) then return end
	Say(ply, "You gave " .. target:Nick() .. " " .. Money(fields.amount) .. ".", false)
	Say(target, ply:Nick() .. " gave you " .. Money(fields.amount) .. ".", false)
end)

local ADMIN = {
	[WS.ADMIN_KICK] = function(ply, target)
		print("[Sandcastle] " .. ply:Nick() .. " kicked " .. target:Nick())
		target:Kick("Kicked by " .. ply:Nick())
		return "Kicked " .. target:Nick() .. "."
	end,
	[WS.ADMIN_BAN] = function(ply, target, value)
		local ban = WS.PLAYERS_MENU_BANS[value + 1]
		if not ban then return nil, "That ban length is not offered." end
		print("[Sandcastle] " .. ply:Nick() .. " banned " .. target:Nick() .. " (" .. ban.label .. ")")
		target:Ban(ban.minutes, true)
		return "Banned " .. target:Nick() .. " (" .. ban.label .. ")."
	end,
	[WS.ADMIN_GRANT] = function(ply, target, value)
		print("[Sandcastle] " .. ply:Nick() .. " gave " .. target:Nick() .. " " .. Money(value))
		WS.GrantMoney(target, value)
		Say(target, "An admin gave you " .. Money(value) .. ".", false)
		return "Gave " .. target:Nick() .. " " .. Money(value) .. "."
	end,
}

E.Listen("admin_player", "ws_players_menu", function(fields, ply)
	if not WS.Can(ply, Permissions.PLAYERS) then return Say(ply, "You may not do that.", true) end
	local target = Target(ply, fields.target)
	if not target then return end
	local act = ADMIN[fields.action]
	if not act then return Say(ply, "That is not something the menu does.", true) end
	if target == ply and fields.action ~= WS.ADMIN_GRANT then return Say(ply, "You cannot do that to yourself.", true) end
	local done, why = act(ply, target, fields.value)
	Say(ply, done or why, done == nil)
end)
